package com.openbitfun.mobile.core.feature.genui

import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LocalGenUiGesturesTest {
    private val app = LocalGenUiApp("app", "session", "Gestures", "", sourceRevision = 2)
    private val host = LocalGenUiGestures()

    @Test
    fun gestureRoutingAndRearming() {
        host.mount(app)
        host.setVisible(true)
        subscribe("left", "raise_left_hand")
        subscribe("right", "raise_right_hand")
        subscribe("both", "raise_both_hands")
        host.cameraStatus(LocalGenUiCameraStatus.ACTIVE)

        assertTrue(host.frame(frame(left = true)).isEmpty())
        assertContains(host.frame(frame(left = true)).single(), """"subscriptionId":"left"""")
        assertTrue(host.frame(frame(left = true, right = true)).isEmpty())
        assertTrue(host.frame(frame(left = true, right = true)).isEmpty())
        host.frame(frame())
        assertTrue(host.frame(frame(right = true, rotated = true)).isEmpty())
        assertContains(host.frame(frame(right = true, rotated = true)).single(), """"subscriptionId":"right"""")
        host.frame(emptyList())
        assertTrue(host.frame(frame(left = true, right = true)).isEmpty())
        assertContains(host.frame(frame(left = true, right = true)).single(), """"subscriptionId":"both"""")
    }

    @Test
    fun cameraRequiresLiveMatchingDocumentAndForegroundSubscription() {
        host.mount(app.copy(checking = true))
        host.setVisible(true)
        assertTrue(subscribe("left", "raise_left_hand").isEmpty())
        host.mount(app)
        assertTrue(subscribe("left", "raise_left_hand", revision = 1).isEmpty())
        assertTrue(subscribe("left", "raise_left_hand", appId = "another").isEmpty())
        assertFalse(host.cameraWanted)

        assertContains(subscribe("left", "raise_left_hand").single(), "starting")
        assertTrue(host.cameraWanted)
        assertContains(host.cameraStatus(LocalGenUiCameraStatus.ACTIVE).single(), "active")
        host.frame(frame(left = true))
        assertContains(host.setVisible(false).single(), "paused")
        assertFalse(host.cameraWanted)
        assertTrue(host.frame(frame(left = true)).isEmpty())
        assertTrue(host.cameraStatus(LocalGenUiCameraStatus.ACTIVE).isEmpty())

        assertContains(host.setVisible(true).single(), "starting")
        host.cameraStatus(LocalGenUiCameraStatus.ACTIVE)
        assertTrue(host.frame(frame(left = true)).isEmpty())
        host.receive("""{"type":"capability","op":"unsubscribe","appId":"app","sourceRevision":2,"subscriptionId":"left","capability":"gesture"}""")
        assertFalse(host.cameraWanted)

        subscribe("left", "raise_left_hand")
        host.mount(app.copy(sourceRevision = 3))
        assertFalse(host.hasSubscriptions)
        assertTrue(subscribe("left", "raise_left_hand").isEmpty())
    }

    @Test
    fun invalidAndExcessSubscriptionsDoNotDisplaceExistingOnes() {
        host.mount(app)
        host.setVisible(true)
        for (i in 1..4) assertContains(subscribe("id-$i", "raise_left_hand").single(), "starting")
        assertContains(subscribe("extra", "raise_left_hand").single(), "unavailable")
        assertContains(subscribe("id-1", "invalid").single(), "unavailable")
        assertEquals(4, host.cameraStatus(LocalGenUiCameraStatus.ACTIVE).size)
        host.frame(frame(left = true))
        assertEquals(4, host.frame(frame(left = true)).size)
    }

    private fun subscribe(id: String, gesture: String, revision: Int = 2, appId: String = "app") =
        host.receive("""{"type":"capability","op":"subscribe","appId":"$appId","sourceRevision":$revision,"subscriptionId":"$id","capability":"gesture","gesture":"$gesture"}""")

    private fun frame(
        left: Boolean = false, right: Boolean = false, rotated: Boolean = false,
    ): List<LocalGenUiPosePoint> {
        fun point(joint: LocalGenUiPoseJoint, x: Double, y: Double) =
            if (rotated) LocalGenUiPosePoint(joint, y, -x, 1.0) else LocalGenUiPosePoint(joint, x, y, 1.0)
        return listOf(
            point(LocalGenUiPoseJoint.NOSE, 100.0, 60.0),
            point(LocalGenUiPoseJoint.LEFT_SHOULDER, 125.0, 100.0),
            point(LocalGenUiPoseJoint.RIGHT_SHOULDER, 75.0, 100.0),
            point(LocalGenUiPoseJoint.LEFT_WRIST, 140.0, if (left) 65.0 else 150.0),
            point(LocalGenUiPoseJoint.RIGHT_WRIST, 60.0, if (right) 65.0 else 150.0),
        )
    }
}
