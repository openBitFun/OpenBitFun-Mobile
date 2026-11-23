package com.openbitfun.mobile.app.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.openbitfun.mobile.app.platform.LogcatCoreLog
import com.openbitfun.mobile.app.platform.LEGACY_MOBILE_DEVICE_NAMES
import com.openbitfun.mobile.app.platform.deviceIdentity
import com.openbitfun.mobile.core.feature.account.AccountIntent
import com.openbitfun.mobile.core.feature.account.AccountStore
import com.openbitfun.mobile.core.feature.account.AccountUiState
import com.openbitfun.mobile.core.feature.account.create
import com.openbitfun.mobile.core.feature.connection.ConnectionPhase
import com.openbitfun.mobile.core.feature.session.RemoteSessionIntent
import com.openbitfun.mobile.core.feature.session.DeviceModelDefaultsUiState
import com.openbitfun.mobile.core.feature.session.RemoteSessionStore
import com.openbitfun.mobile.core.feature.session.RemoteSessionUiState
import com.openbitfun.mobile.core.feature.session.CommandPaletteUiState
import com.openbitfun.mobile.core.feature.session.WorkspaceSessionDirectoryUiState
import com.openbitfun.mobile.core.feature.workspace.RemoteWorkspaceIntent
import com.openbitfun.mobile.core.feature.workspace.RemoteWorkspaceStore
import com.openbitfun.mobile.core.feature.workspace.RemoteWorkspaceUiState
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

internal class AccountViewModel(application: Application) : AndroidViewModel(application) {
    private val completionNotifier = com.openbitfun.mobile.app.platform.TaskCompletionNotifier(application)
    private var foreground = true
    fun setBackground(value: Boolean) {
        LogcatCoreLog.info("account host visibility foreground=${!value}")
        store.setForeground(!value)
        if (!value) store.resumeSessionStreams()
        foreground = !value
        completionNotifier.setBackground(value)
        remoteStore?.dispatch(RemoteSessionIntent.SetForeground(foreground))
    }
    private val identity = application.deviceIdentity()
    private val store = AccountStore.create(
        viewModelScope,
        application,
        identity.installId,
        identity.displayName,
        LogcatCoreLog,
        LEGACY_MOBILE_DEVICE_NAMES,
    )
    val state: StateFlow<AccountUiState> = store.state
    private val _remoteState = MutableStateFlow<RemoteSessionUiState>(RemoteSessionUiState.Idle)
    val remoteState: StateFlow<RemoteSessionUiState> = _remoteState.asStateFlow()
    private val _commandPalette = MutableStateFlow(CommandPaletteUiState.empty())
    val commandPalette: StateFlow<CommandPaletteUiState> = _commandPalette.asStateFlow()
    private val _deviceModels = MutableStateFlow(DeviceModelDefaultsUiState())
    val deviceModels: StateFlow<DeviceModelDefaultsUiState> = _deviceModels.asStateFlow()
    private val _connectionPhase = MutableStateFlow(ConnectionPhase.IDLE)
    val connectionPhase: StateFlow<ConnectionPhase> = _connectionPhase.asStateFlow()
    private val _workspaceState = MutableStateFlow<RemoteWorkspaceUiState>(RemoteWorkspaceUiState.Idle)
    val workspaceState: StateFlow<RemoteWorkspaceUiState> = _workspaceState.asStateFlow()
    private val _workspaceDirectory = MutableStateFlow(WorkspaceSessionDirectoryUiState(emptyList()))

    /** Per-workspace session lists, filled in as the sidebar discloses each branch. */
    val workspaceDirectory: StateFlow<WorkspaceSessionDirectoryUiState> = _workspaceDirectory.asStateFlow()
    private var remoteStore: RemoteSessionStore? = null
    private var workspaceStore: RemoteWorkspaceStore? = null
    private var remoteJob: Job? = null
    private var deviceModelsJob: Job? = null
    private var connectionJob: Job? = null
    private var directoryJob: Job? = null
    private var workspaceJob: Job? = null
    private var activeTarget: String? = null
    // The selected device the user disconnected from. The selection stays so the
    // card can offer it again, but account churn must not bind it back.
    private var releasedTarget: String? = null

    init {
        viewModelScope.launch {
            store.state.collect { current ->
                val ready = current as? AccountUiState.Ready
                val selected = ready?.selectedDeviceId
                if (selected != releasedTarget) releasedTarget = null
                val target = selected.takeIf { id ->
                    id != releasedTarget && ready?.devices?.any { it.id == id && it.controllable } == true
                }
                if (target != activeTarget) bindTarget(target)
            }
        }
        store.dispatch(AccountIntent.Restore)
    }

    fun dispatch(intent: AccountIntent) {
        store.dispatch(intent)
    }

    fun notifyAuthorizationCallback() {
        LogcatCoreLog.info("account authorization callback wakeup")
        store.notifyAuthorizationCallback()
    }

    /** The handle General Chat reads the account's synced models through. */

    fun dispatchSession(intent: RemoteSessionIntent) {
        remoteStore?.dispatch(intent)
    }

    fun dispatchDeviceModels(deviceId: String, intent: RemoteSessionIntent) {
        val selected = (state.value as? AccountUiState.Ready)?.selectedDeviceId
        if (deviceId == selected && deviceId == activeTarget) remoteStore?.dispatch(intent)
    }

    fun dispatchWorkspace(intent: RemoteWorkspaceIntent) {
        workspaceStore?.dispatch(intent)
    }

    /**
     * Point the session and workspace stores at [deviceId], rebuilding them even
     * when it is already the selected device.
     *
     * The collector above only rebinds when `selectedDeviceId` changes, which is
     * right for ordinary account churn but makes the row inert exactly when it
     * matters: selecting the device that is already selected produces an
     * identical state, so nothing rebinds and a failed load has no way back.
     * `canSelectAccountDevice` in `ConnectAccountDevicePage.ets` has no such
     * guard, and a row that reads "Controlling" while nothing loaded has to be
     * a way back.
     */
    fun selectDevice(deviceId: String) {
        val ready = state.value as? AccountUiState.Ready ?: return
        val device = ready.devices.firstOrNull { it.id == deviceId && it.controllable } ?: return
        if (deviceId == activeTarget || deviceId == releasedTarget) {
            releasedTarget = null
            bindTarget(deviceId)
        } else {
            // Clear the outgoing projection before publishing the new selection.
            // The account collector binds the new target's shared stores.
            if (!device.online) return
            remoteStore?.dispatch(RemoteSessionIntent.CloseDeviceModelDefaults)
            deviceModelsJob?.cancel()
            _deviceModels.value = DeviceModelDefaultsUiState()
            remoteJob?.cancel()
            workspaceJob?.cancel()
            connectionJob?.cancel()
            directoryJob?.cancel()
            _workspaceDirectory.value = WorkspaceSessionDirectoryUiState(emptyList())
            _remoteState.value = RemoteSessionUiState.Loading
            _workspaceState.value = RemoteWorkspaceUiState.Loading
            _connectionPhase.value = ConnectionPhase.IDLE
            store.dispatch(AccountIntent.SelectDevice(deviceId))
        }
    }

    fun disconnectDevice() {
        releasedTarget = activeTarget
        bindTarget(null)
    }

    private fun bindTarget(target: String?) {
        remoteJob?.cancel()
        deviceModelsJob?.cancel()
        connectionJob?.cancel()
        workspaceJob?.cancel()
        directoryJob?.cancel()
        remoteStore?.dispatch(RemoteSessionIntent.Stop)
        workspaceStore?.dispatch(RemoteWorkspaceIntent.Stop)
        remoteStore = null
        workspaceStore = null
        _remoteState.value = RemoteSessionUiState.Idle
        _commandPalette.value = CommandPaletteUiState.empty()
        _deviceModels.value = DeviceModelDefaultsUiState()
        _connectionPhase.value = ConnectionPhase.IDLE
        _workspaceState.value = RemoteWorkspaceUiState.Idle
        _workspaceDirectory.value = WorkspaceSessionDirectoryUiState(emptyList())
        completionNotifier.reset()
        activeTarget = target
        if (target == null) return

        remoteStore = store.createSessionStore(viewModelScope)?.also { created ->
            remoteJob = viewModelScope.launch { created.state.collect {
                _remoteState.value = it
                completionNotifier.observe(it, target)
            } }
            viewModelScope.launch { created.commandPalette.collect { _commandPalette.value = it } }
            connectionJob = viewModelScope.launch {
                created.connectionPhase.collect { _connectionPhase.value = it }
            }
            deviceModelsJob = viewModelScope.launch {
                created.deviceModelDefaults.collect { _deviceModels.value = it }
            }
            directoryJob = viewModelScope.launch {
                created.workspaceDirectory.collect { _workspaceDirectory.value = it }
            }
            created.dispatch(RemoteSessionIntent.Load)
            created.dispatch(RemoteSessionIntent.SetForeground(foreground))
        }
        workspaceStore = store.createWorkspaceStore(viewModelScope)?.also { created ->
            workspaceJob = viewModelScope.launch { created.state.collect { _workspaceState.value = it } }
            created.dispatch(RemoteWorkspaceIntent.Load)
        }
    }

    override fun onCleared() {
        bindTarget(null)
        store.stop()
        super.onCleared()
    }

    companion object {
        val Factory: ViewModelProvider.Factory = object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(
                modelClass: Class<T>,
                extras: androidx.lifecycle.viewmodel.CreationExtras,
            ): T = AccountViewModel(
                extras[ViewModelProvider.AndroidViewModelFactory.APPLICATION_KEY]!!,
            ) as T
        }
    }
}
