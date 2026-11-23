package com.openbitfun.mobile.app.ui.genui

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Build.VERSION_CODES
import android.os.ext.SdkExtensions
import com.openbitfun.mobile.core.feature.genui.LocalGenUiCollaboration
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import java.net.Inet4Address
import kotlin.coroutines.resume

internal data class NearbyImageAddress(val address: String, val port: Int)

/** Platform DNS-SD service information is untrusted until the transfer is verified. */
internal class LocalGenUiNearbyImages(context: Context) {
    private val manager = context.getSystemService(NsdManager::class.java)
    private val wifi = context.applicationContext.getSystemService(WifiManager::class.java)
    private val serviceType = LocalGenUiCollaboration.NEARBY_SERVICE_TYPE + "."

    fun browse(): Flow<List<NsdServiceInfo>> = callbackFlow {
        val nsd = manager ?: run { close(); return@callbackFlow }
        val lock = if (Build.VERSION.SDK_INT < 33 || SdkExtensions.getExtensionVersion(VERSION_CODES.TIRAMISU) < 7) {
            runCatching { wifi?.createMulticastLock("openbitfun-image")?.apply { acquire() } }.getOrNull()
        } else null
        val devices = LinkedHashMap<String, NsdServiceInfo>()
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) = Unit
            override fun onDiscoveryStopped(serviceType: String) = Unit
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) { close() }
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) { close() }
            override fun onServiceFound(service: NsdServiceInfo) {
                if (service.serviceType.trimEnd('.') != serviceType.trimEnd('.')) return
                if (devices.size < 32 || service.serviceName in devices) {
                    devices[service.serviceName] = service
                    trySend(devices.values.sortedBy { it.serviceName })
                }
            }
            override fun onServiceLost(service: NsdServiceInfo) {
                devices.remove(service.serviceName)
                trySend(devices.values.sortedBy { it.serviceName })
            }
        }
        try { nsd.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, listener) }
        catch (_: RuntimeException) { close() }
        awaitClose {
            runCatching { nsd.stopServiceDiscovery(listener) }
            lock?.release()
        }
    }

    fun publish(address: String, port: Int): Flow<Boolean> = callbackFlow {
        val nsd = manager ?: run { close(); return@callbackFlow }
        val service = NsdServiceInfo().apply {
            serviceName = Build.MODEL.trim().takeIf { it.isNotEmpty() && it.toByteArray().size <= 63 } ?: "Android"
            serviceType = this@LocalGenUiNearbyImages.serviceType
            setPort(port)
            setAttribute("ip", address)
            setAttribute("port", port.toString())
        }
        val listener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(serviceInfo: NsdServiceInfo) { trySend(true) }
            override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) = Unit
            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) { close() }
            override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) { close() }
        }
        try { nsd.registerService(service, NsdManager.PROTOCOL_DNS_SD, listener) }
        catch (_: RuntimeException) { close() }
        awaitClose { runCatching { nsd.unregisterService(listener) } }
    }

    @Suppress("DEPRECATION")
    suspend fun resolve(service: NsdServiceInfo): NearbyImageAddress? =
        suspendCancellableCoroutine { continuation ->
            val nsd = manager ?: run { continuation.resume(null); return@suspendCancellableCoroutine }
            val listener = object : NsdManager.ResolveListener {
                override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) {
                    if (continuation.isActive) continuation.resume(null)
                }

                override fun onServiceResolved(info: NsdServiceInfo) {
                    val hosts = if (Build.VERSION.SDK_INT >= VERSION_CODES.UPSIDE_DOWN_CAKE) info.hostAddresses
                        else listOfNotNull(info.host)
                    val address = hosts.filterIsInstance<Inet4Address>()
                        .mapNotNull { it.hostAddress }
                        .firstOrNull(LocalGenUiCollaboration::localAddress)
                    if (continuation.isActive) continuation.resume(
                        address?.takeIf { info.port in 1024..65535 }?.let { NearbyImageAddress(it, info.port) }
                    )
                }
            }
            try { nsd.resolveService(service, listener) }
            catch (_: RuntimeException) { if (continuation.isActive) continuation.resume(null) }
        }
}
