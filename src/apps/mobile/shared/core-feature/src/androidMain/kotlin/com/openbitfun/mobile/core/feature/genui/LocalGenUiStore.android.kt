package com.openbitfun.mobile.core.feature.genui

import android.content.Context
import com.openbitfun.mobile.core.persistence.androidPersistenceStores
import com.openbitfun.mobile.core.persistence.androidSecureStore
import com.openbitfun.mobile.core.transport.GenUiProviderStream
import kotlinx.coroutines.CoroutineScope

public fun LocalGenUiStore.Companion.create(scope: CoroutineScope, context: Context): LocalGenUiStore {
    val application = context.applicationContext
    val assets = application.assets
    return LocalGenUiStore(
        scope, androidPersistenceStores(application, "openbitfun-local-genui.db").drafts,
        androidSecureStore(application, "local-genui"),
        assets.open("genui/harmony-prompt.txt").bufferedReader().use { it.readText() },
        assets.open("genui/local-tool-schema.json").bufferedReader().use { it.readText() },
        GenUiProviderStream.create(),
    )
}
