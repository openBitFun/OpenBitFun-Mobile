package com.openbitfun.mobile.core.feature.genui

import com.openbitfun.mobile.core.persistence.iosPersistenceStores
import com.openbitfun.mobile.core.persistence.iosSecureStore
import com.openbitfun.mobile.core.transport.GenUiProviderStream
import kotlinx.coroutines.CoroutineScope

public fun LocalGenUiStore.Companion.create(scope: CoroutineScope, prompt: String, schema: String): LocalGenUiStore =
    LocalGenUiStore(
        scope, iosPersistenceStores("openbitfun-local-genui.db").drafts,
        iosSecureStore("com.openbitfun.mobile.localgenui"), prompt, schema, GenUiProviderStream.create(),
    )
