package com.openbitfun.mobile.core.transport

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.int
import java.nio.file.Files
import java.nio.file.Path
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Pins the compiled Kotlin build identity to the shared wire contracts and to
 * every Kotlin transport entry point that must send it. Cross-platform source
 * contracts live in `scripts/mobile-client-build.contract.test.mjs`.
 */
class ClientBuildContractTest {
    private val repoRoot: Path = generateSequence(Path.of("").toAbsolutePath()) { it.parent }
        .first { Files.exists(it.resolve("contracts/client-protocol.json")) && Files.exists(it.resolve("package.json")) }

    private fun source(relative: String): String = Files.readString(repoRoot.resolve(relative))

    @Test
    fun protocolVersionMatchesThePinnedHostContract() {
        val contract = Json.parseToJsonElement(source("contracts/client-protocol.json")).jsonObject
        assertEquals(CLIENT_PROTOCOL_VERSION, contract.getValue("clientProtocolVersion").jsonPrimitive.int)
    }

    @Test
    fun clientVersionIsTheWorkspaceReleaseVersion() {
        val packageVersion = Regex("\"version\"\\s*:\\s*\"([^\"]+)\"").find(source("package.json"))!!.groupValues[1]
        assertEquals(packageVersion, CLIENT_VERSION)
        assertTrue(Regex("^\\d+\\.\\d+\\.\\d+").containsMatchIn(CLIENT_VERSION))
        assertTrue(CLIENT_VERSION.length <= 64)
    }

    @Test
    fun kotlinTransportReportsTheBuildOnLoginAndOnEveryHandshake() {
        val transport = "src/apps/mobile/shared/core-transport/src/commonMain/kotlin/com/openbitfun/mobile/core/transport"
        val realtime = source("$transport/AccountRealtime.kt")
        assertTrue(realtime.contains("put(\"clientVersion\", CLIENT_VERSION)"))
        assertTrue(realtime.contains("put(\"clientProtocol\", CLIENT_PROTOCOL_VERSION)"))
        val client = source("$transport/CloudAccountClient.kt")
        assertTrue(client.contains("@SerialName(\"clientVersion\") val clientVersion: String"))
        assertTrue(client.contains("@SerialName(\"clientProtocol\") val clientProtocol: Int"))
        assertTrue(client.contains("CLIENT_VERSION, CLIENT_PROTOCOL_VERSION"))
    }
}
