package com.openbitfun.mobile.core.feature.genui

import kotlinx.cinterop.BetaInteropApi
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.usePinned
import platform.Foundation.NSData
import platform.Foundation.create

@OptIn(ExperimentalForeignApi::class, BetaInteropApi::class)
public fun LocalGenUiImage.toNSData(): NSData =
    bytes.usePinned { NSData.create(bytes = it.addressOf(0), length = bytes.size.toULong()) }
