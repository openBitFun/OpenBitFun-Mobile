import XCTest

final class RemoteCodeSessionSendUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }

    func testSendMessageInCurrentRemoteCodeSession() throws {
        let activeSession = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "conversation.session.")
        ).firstMatch
        guard activeSession.waitForExistence(timeout: 20) else {
            recordDiagnostics(named: "NoActiveRemoteSession")
            XCTFail(
                "No active Remote Code Session is visible. Keep the phone unlocked and navigate OpenBitFun to the intended existing remote code session; this test will not choose a session automatically."
            )
            return
        }

        let composer = app.textFields.firstMatch
        guard composer.waitForExistence(timeout: 10), composer.isHittable else {
            recordDiagnostics(named: "ComposerUnavailable")
            XCTFail("The current remote session is visible, but its composer text field is unavailable or obstructed.")
            return
        }

        let message = "iPhone remote send E2E \(Int(Date().timeIntervalSince1970))"
        composer.tap()
        composer.typeText(message)
        XCTAssertEqual(composer.value as? String, message, "The complete harmless E2E message was not entered.")

        let sendButton = firstExistingElement([
            app.buttons["发送"],
            app.buttons["Send"],
        ])
        guard let sendButton else {
            recordDiagnostics(named: "SendButtonMissing")
            XCTFail("The composer contains the E2E message, but no localized Send button is visible.")
            return
        }
        guard sendButton.isEnabled else {
            recordDiagnostics(named: "SendButtonDisabled")
            XCTFail("The Send button is disabled; remote mutation authority may not be confirmed or the session may be busy. The draft was not dispatched.")
            return
        }

        sendButton.tap()

        let draftCleared = NSPredicate { evaluated, _ in
            guard let field = evaluated as? XCUIElement else { return false }
            return (field.value as? String) != message
        }
        expectation(for: draftCleared, evaluatedWith: composer)
        waitForExpectations(timeout: 10)

        let timelineMessage = app.staticTexts[message]
        guard timelineMessage.waitForExistence(timeout: 20) else {
            recordDiagnostics(named: "TimelineMessageMissing")
            XCTFail("The draft cleared after tapping Send, but the exact E2E message did not appear in the current timeline; dispatch or peer synchronization may have failed.")
            return
        }

        let evidence = XCTAttachment(string: "Sent message visible in current timeline: \(message)")
        evidence.name = "RemoteCodeSessionSendEvidence"
        evidence.lifetime = .keepAlways
        add(evidence)
        recordDiagnostics(named: "RemoteCodeSessionSendSucceeded")
    }

    private func firstExistingElement(_ elements: [XCUIElement]) -> XCUIElement? {
        elements.first { $0.waitForExistence(timeout: 2) }
    }

    private func recordDiagnostics(named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name)-Hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}

/// Read-only real-device probe for the remote-create critical path. It opens
/// the workspace picker and observes its first usable row, but never selects a
/// workspace, creates a session, or sends content.
final class RemoteWorkspaceLoadingPerformanceUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
    private var startedAt = Date()

    override func setUpWithError() throws {
        continueAfterFailure = false
        startedAt = Date()
        app.launch()
    }

    func testConnectedHomeToWorkspaceRowsReadOnly() throws {
        let connected = firstExistingElement([
            app.staticTexts["桌面端已连接"],
            app.staticTexts["Desktop connected"],
        ], timeout: 30)
        XCTAssertNotNil(connected, "The existing remote connection did not restore on the device.")
        recordMilestone("connected_home")

        guard let create = firstExistingElement([
            app.buttons["新建远程会话"],
            app.buttons["New remote session"],
        ], timeout: 10) else {
            recordDiagnostics(named: "RemoteCreateActionMissing")
            XCTFail("The connected home did not expose the remote-create action.")
            return
        }
        XCTAssertTrue(create.isHittable)
        create.tap()
        recordMilestone("create_opened")

        let selectors = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "remoteCreate.workspace.")
        )
        let selector = selectors.firstMatch
        let usableSelector = NSPredicate { evaluated, _ in
            guard let element = evaluated as? XCUIElement else { return false }
            return element.exists && element.isHittable && element.isEnabled
        }
        expectation(for: usableSelector, evaluatedWith: selector)
        waitForExpectations(timeout: 15)
        XCTAssertEqual(selectors.count, 1, "Workspace selector must be unambiguous.")
        recordMilestone("workspace_selector_usable")

        selector.tap()
        recordMilestone("workspace_picker_opened")

        let workspaceRows = app.buttons.matching(
            NSPredicate(
                format: "label BEGINSWITH %@ OR label BEGINSWITH %@",
                "工作区:",
                "Workspace:"
            )
        )
        let firstRow = workspaceRows.firstMatch
        let usableRow = NSPredicate { evaluated, _ in
            guard let element = evaluated as? XCUIElement else { return false }
            return element.exists && element.isHittable && element.isEnabled
        }
        expectation(for: usableRow, evaluatedWith: firstRow)
        waitForExpectations(timeout: 45)
        recordMilestone("first_workspace_row_usable")
        recordDiagnostics(named: "WorkspaceRowsReadOnlySucceeded")
    }

    private func firstExistingElement(_ elements: [XCUIElement], timeout: TimeInterval) -> XCUIElement? {
        elements.first { $0.waitForExistence(timeout: timeout) }
    }

    private func recordMilestone(_ name: String) {
        let elapsed = Date().timeIntervalSince(startedAt)
        let attachment = XCTAttachment(string: String(format: "%@ +%.3fs", name, elapsed))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func recordDiagnostics(named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name)-Hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}

final class RemoteCreateWorkspacePickerUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--harness-preview", "--remote-create"]
        app.launchMobileReady()
    }

    func testWorkspacePickerOpensAndExposesUsableRows() {
        assertWorkspacePickerUsable()
    }

    func testSessionDirectoryBusyDoesNotDisableWorkspacePicker() {
        app.terminate()
        app.launchArguments = ["--harness-preview", "--remote-create-session-loading"]
        app.launchMobileReady()
        assertWorkspacePickerUsable()
    }

    private func assertWorkspacePickerUsable() {
        let selectors = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "remoteCreate.workspace.")
        )
        let selector = selectors.firstMatch
        XCTAssertTrue(selector.waitForExistence(timeout: 10))
        XCTAssertEqual(selectors.count, 1)
        XCTAssertTrue(selector.isHittable)
        XCTAssertTrue(selector.isEnabled, "Independent session loading must not disable the workspace selector.")

        selector.tap()

        let workspaceRows = app.buttons.matching(
            NSPredicate(
                format: "label BEGINSWITH %@ OR label BEGINSWITH %@",
                "工作区:",
                "Workspace:"
            )
        )
        let row = workspaceRows.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.isHittable)
        XCTAssertTrue(row.isEnabled)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "RemoteCreateWorkspacePickerUsable"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

/// Read-only responsiveness probes for the two composer implementations. The
/// tests enter a disposable character but never submit it or mutate a remote
/// session.
final class ComposerFocusResponsivenessUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRemoteConversationComposerAcceptsFirstCharacter() {
        app.launchArguments = ["--harness-preview", "--remote", "--connected"]
        app.launchMobileReady()
        assertFirstCharacterResponsiveness(
            identifier: "composer.input",
            named: "RemoteHomeComposer"
        )
    }

    func testRemoteCreateComposerAcceptsFirstCharacter() {
        app.launchArguments = ["--harness-preview", "--remote-create"]
        app.launchMobileReady()
        assertFirstCharacterResponsiveness(
            identifier: "remoteCreate.composer.input",
            named: "RemoteCreateComposer"
        )
    }

    private func assertFirstCharacterResponsiveness(identifier: String, named name: String) {
        let field = app.textFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "\(name) text field did not appear.")
        XCTAssertTrue(field.isHittable, "\(name) text field is obstructed.")

        let tapStart = Date()
        field.tap()
        let tapElapsed = Date().timeIntervalSince(tapStart)

        let typeStart = Date()
        field.typeText("x")
        let typeElapsed = Date().timeIntervalSince(typeStart)

        XCTAssertEqual(field.value as? String, "x", "\(name) did not accept the first character.")
        XCTAssertLessThan(tapElapsed, 2, "\(name) focus transition blocked UI automation.")
        XCTAssertLessThan(typeElapsed, 2, "\(name) first character handling blocked UI automation.")
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            XCTAssertLessThanOrEqual(
                field.frame.maxY,
                keyboard.frame.minY + 1,
                "\(name) is covered by the software keyboard."
            )
        }

        let timing = XCTAttachment(
            string: String(format: "tap=%.3fs type=%.3fs keyboards=%d", tapElapsed, typeElapsed, app.keyboards.count)
        )
        timing.name = "\(name)-Timing"
        timing.lifetime = .keepAlways
        add(timing)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "\(name)-Focused"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

/// Exercises the complete account-driven remote workflow against a real relay.
/// Credentials are supplied by the invoking process and are never persisted in
/// the test bundle or emitted in diagnostics.
final class RemoteAccountWorkflowPerformanceUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
    private var workflowStartedAt = Date()

    override func setUpWithError() throws {
        continueAfterFailure = false
        workflowStartedAt = Date()
        app.launchArguments = ["--simplified-chinese", "--drawer"]
        app.launch()
    }

    func testLoginDeviceWorkspaceSessionSwitchAndSend() throws {
        let environment = ProcessInfo.processInfo.environment
        let username = environment["OPENBITFUN_E2E_USERNAME"] ?? ""
        let password = environment["OPENBITFUN_E2E_PASSWORD"] ?? ""
        if (!app.launchArguments.contains("--drawer")) && (username.isEmpty || password.isEmpty) {
            throw XCTSkip("Set OPENBITFUN_E2E_USERNAME and OPENBITFUN_E2E_PASSWORD to run the real relay workflow.")
        }
        let sidebarAlreadyOpen = try signIn(username: username, password: password)
        let deviceID = try selectFirstRemoteDevice(openSidebar: !sidebarAlreadyOpen)
        let sessionIDs = try exerciseWorkspaceDirectory(deviceID: deviceID)
        try exerciseSessionSwitching(sessionIDs: sessionIDs)
        _ = try sendVerificationMessage()
        try exerciseCommandPalette()
        let idleStarted = Date()
        RunLoop.current.run(until: Date().addingTimeInterval(5))
        recordStep("post_workflow_idle", since: idleStarted)
        recordDiagnostics(named: "RemoteAccountWorkflowSucceeded")
    }

    private func signIn(username: String, password: String) throws -> Bool {
        if app.launchArguments.contains("--drawer") {
            recordStep("account_restore_ready", since: workflowStartedAt)
            return true
        }
        if app.buttons["查看设备"].exists || app.buttons["View devices"].exists {
            let viewDevices = app.buttons["查看设备"].exists ? app.buttons["查看设备"] : app.buttons["View devices"]
            viewDevices.tap()
            recordStep("device_directory_opened", since: workflowStartedAt)
            return false
        }
        let sidebar = try requireFirst([
            app.buttons["打开侧栏"],
            app.buttons["Open sidebar"],
        ], timeout: 20, failure: "The sidebar action did not become available.")
        tapEvenIfCovered(sidebar)

        let accountActions = [
            app.buttons["登录 OpenBitFun 账号"],
            app.buttons["Sign in to OpenBitFun"],
        ]
        if !waitUntil(timeout: 5, condition: {
            accountActions.contains(where: \.exists) || self.app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "sidebar.device.")
            ).count > 0
        }) {
            recordDiagnostics(named: "AccountStateUnavailable")
            XCTFail("The sidebar exposed neither account login nor a restored device directory.")
            throw WorkflowError.requiredElementMissing
        }
        if !accountActions.contains(where: \.exists) {
            recordStep("account_restore_ready", since: workflowStartedAt)
            return true
        }
        let accountAction = accountActions.first(where: \.exists)!
        accountAction.tap()

        let usernameField = try requireFirst([
            app.textFields["用户名"],
            app.textFields["Username"],
        ], timeout: 10, failure: "The username field did not appear.")
        let passwordField = try requireFirst([
            app.secureTextFields["密码"],
            app.secureTextFields["Password"],
        ], timeout: 10, failure: "The password field did not appear.")
        usernameField.tap()
        usernameField.typeText(username)
        passwordField.tap()
        passwordField.typeText(password)

        let login = try requireFirst([
            app.buttons["登录"],
            app.buttons["Sign in"],
        ], timeout: 5, failure: "The login button did not become available.")
        XCTAssertTrue(login.isEnabled, "The completed login form remained disabled.")
        let started = Date()
        login.tap()

        _ = try requireFirst([
            app.staticTexts["个人资料"],
            app.staticTexts["Profile"],
        ], timeout: 45, failure: "Login did not reach the account profile.")
        recordStep("login_ready", since: started)

        let close = try requireFirst([
            app.buttons["关闭"],
            app.buttons["Close"],
        ], timeout: 5, failure: "The account sheet could not be closed.")
        close.tap()
        _ = try requireFirst([
            app.buttons["打开侧栏"],
            app.buttons["Open sidebar"],
        ], timeout: 10, failure: "The conversation surface did not return after login.")
        return false
    }

    private func selectFirstRemoteDevice(openSidebar: Bool) throws -> String {
        if openSidebar {
            let sidebar = try requireFirst([
                app.buttons["打开侧栏"],
                app.buttons["Open sidebar"],
            ], timeout: 10, failure: "The sidebar action was unavailable after login.")
            sidebar.tap()
        }

        let devices = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "sidebar.device.")
        )
        let deadline = Date().addingTimeInterval(30)
        var device: XCUIElement?
        while Date() < deadline, device == nil {
            for index in 0..<devices.count {
                let candidate = devices.element(boundBy: index)
                let status = candidate.value as? String
                if candidate.exists && candidate.isEnabled && status == "在线" {
                    device = candidate
                    break
                }
            }
            if device == nil { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        }
        guard let device else {
            recordDiagnostics(named: "UsableElementMissing")
            XCTFail("No online account device became selectable.")
            throw WorkflowError.requiredElementMissing
        }
        let identifier = device.identifier
        let deviceID = String(identifier.dropFirst("sidebar.device.".count))
        let started = Date()
        tapEvenIfCovered(device)

        let workspaces = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "sidebar.workspace.\(deviceID).")
        )
        _ = try requireUsableElement(
            in: workspaces,
            timeout: 45,
            failure: "The selected device did not expose a usable workspace."
        )
        recordStep("device_workspaces_ready", since: started)
        return deviceID
    }

    private func exerciseWorkspaceDirectory(deviceID: String) throws -> [String] {
        let workspacePrefix = "sidebar.workspace.\(deviceID)."
        let sessionPrefix = "sidebar.session.\(deviceID)."
        let workspaces = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", workspacePrefix)
        )
        XCTAssertGreaterThan(workspaces.count, 1, "At least two workspaces are required to validate switching.")

        var chosenWorkspace: XCUIElement?
        var sessionIDs: [String] = []
        let candidateCount = min(workspaces.count, 8)
        for index in 0..<candidateCount {
            let workspace = workspaces.element(boundBy: index)
            guard scrollToHittable(workspace) else { continue }
            let started = Date()
            workspace.tap()
            waitForDirectoryLoadingToFinish(timeout: 30)
            recordStep("workspace_\(index + 1)_expanded", since: started)

            let sessions = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", sessionPrefix)
            )
            sessionIDs = uniqueIdentifiers(from: sessions)
            if sessionIDs.count >= 2 {
                chosenWorkspace = workspace
                break
            }

            if scrollToHittable(workspace) { workspace.tap() }
        }

        guard let chosenWorkspace else {
            recordDiagnostics(named: "NoWorkspaceWithTwoSessions")
            XCTFail("No inspected workspace exposed two sessions for rapid switching.")
            return []
        }

        if scrollToHittable(chosenWorkspace) { chosenWorkspace.tap() }
        let secondWorkspace = workspaces.element(boundBy: 1)
        guard scrollToHittable(secondWorkspace) else {
            XCTFail("A second workspace exists but could not be scrolled into view.")
            return []
        }
        let switchStarted = Date()
        secondWorkspace.tap()
        waitForDirectoryLoadingToFinish(timeout: 30)
        recordStep("workspace_switch_ready", since: switchStarted)

        if scrollToHittable(secondWorkspace) { secondWorkspace.tap() }
        guard scrollToHittable(chosenWorkspace) else {
            XCTFail("The source workspace could not be restored after switching.")
            return []
        }
        chosenWorkspace.tap()
        waitForDirectoryLoadingToFinish(timeout: 30)
        return Array(sessionIDs.prefix(3))
    }

    private func exerciseSessionSwitching(sessionIDs: [String]) throws {
        guard sessionIDs.count >= 2 else {
            XCTFail("Rapid switching requires at least two sessions.")
            return
        }

        try openSession(sessionIDs[0], step: "session_first_ready")
        try reopenSidebar()
        try selectSessionWithoutWaiting(sessionIDs[1], step: "rapid_switch_first_selected")
        try reopenSidebar()
        let finalSession = sessionIDs.count > 2 ? sessionIDs[2] : sessionIDs[0]
        try openSession(finalSession, step: "rapid_switch_final_ready")
        try reopenSidebar()
        try openSession(sessionIDs[0], step: "cached_session_return_ready")
        try reopenSidebar()
        try openSession(finalSession, step: "cached_final_session_ready")
        try selectIdleSession(from: sessionIDs)
    }

    private func openSession(_ sessionID: String, step: String) throws {
        let session = app.buttons[sessionID]
        guard scrollToHittable(session) else {
            recordDiagnostics(named: "SessionUnavailable")
            XCTFail("The requested session was not reachable in the expanded workspace.")
            return
        }
        let rawID = sessionID.components(separatedBy: ".").last ?? sessionID
        let started = Date()
        session.tap()

        let conversation = app.descendants(matching: .any)["conversation.session.\(rawID)"]
        XCTAssertTrue(
            waitUntil(timeout: 10) { conversation.exists },
            "The selected conversation identity did not update."
        )
        waitForConversationLoadingToFinish(timeout: 45)
        let composer = app.textFields["composer.input"]
        XCTAssertTrue(
            waitUntil(timeout: 10) { composer.exists && composer.isHittable },
            "The selected conversation composer did not become available."
        )
        XCTAssertTrue(
            waitUntil(timeout: 45) {
                let voice = self.app.buttons["语音输入"]
                let stop = self.app.buttons["停止"]
                return (voice.exists && voice.isEnabled) || (stop.exists && stop.isEnabled)
            },
            "The selected conversation remained busy after its content appeared."
        )
        recordStep(step, since: started)
    }

    private func selectSessionWithoutWaiting(_ sessionID: String, step: String) throws {
        let session = app.buttons[sessionID]
        guard scrollToHittable(session) else {
            XCTFail("The rapid-switch source session was unreachable.")
            return
        }
        let rawID = sessionID.components(separatedBy: ".").last ?? sessionID
        let started = Date()
        session.tap()
        let conversation = app.descendants(matching: .any)["conversation.session.\(rawID)"]
        XCTAssertTrue(
            waitUntil(timeout: 10) { conversation.exists },
            "The rapid-switch source selection was not projected."
        )
        recordStep(step, since: started)
    }

    private func selectIdleSession(from sessionIDs: [String]) throws {
        for (index, sessionID) in sessionIDs.enumerated() {
            try reopenSidebar()
            try openSession(sessionID, step: "send_candidate_\(index + 1)_ready")
            let voice = app.buttons["语音输入"]
            if voice.exists && voice.isEnabled { return }
            let send = app.buttons["发送"]
            XCTAssertFalse(
                send.exists && send.isEnabled,
                "A session with an active turn unexpectedly allowed another send."
            )
        }
        recordDiagnostics(named: "NoIdleSessionForSend")
        XCTFail("All inspected sessions still had active turns, so the verification message was not dispatched.")
        throw WorkflowError.requiredElementMissing
    }

    private func reopenSidebar() throws {
        let action = try requireFirst([
            app.buttons["打开侧栏"],
            app.buttons["Open sidebar"],
        ], timeout: 10, failure: "The sidebar could not be reopened while switching sessions.")
        action.tap()
        let sessions = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "sidebar.session.")
        )
        _ = try requireUsableElement(in: sessions, timeout: 10, failure: "Expanded sessions were not restored in the sidebar.")
    }

    private func sendVerificationMessage() throws -> String {
        let composer = app.textFields["composer.input"]
        XCTAssertTrue(waitUntil(timeout: 10) { composer.exists }, "The composer was unavailable before send.")
        XCTAssertTrue(composer.isHittable, "The composer was obstructed before send.")

        let message = "iOS 模拟器端到端性能验证 \(Int(Date().timeIntervalSince1970))"
        composer.tap()
        composer.typeText(message)
        XCTAssertEqual(composer.value as? String, message)

        let send = try requireFirst([
            app.buttons["发送"],
            app.buttons["Send"],
        ], timeout: 5, failure: "The Send button did not become available after typing.")
        XCTAssertTrue(send.isEnabled, "The selected session did not allow message sending.")
        let started = Date()
        send.tap()

        XCTAssertTrue(
            waitUntil(timeout: 10) { (composer.value as? String) != message },
            "The draft did not clear after dispatch."
        )
        recordStep("send_draft_cleared", since: started)

        let timelineMessage = app.staticTexts[message]
        XCTAssertTrue(
            waitUntil(timeout: 30) { timelineMessage.exists },
            "The submitted message did not appear in the active timeline."
        )
        recordStep("send_message_visible", since: started)
        return message
    }

    private func exerciseCommandPalette() throws {
        let usage = try requireFirst([app.buttons["会话用量"]], timeout: 10, failure: "The usage command chip did not appear.")
        let skills = try requireFirst([app.buttons["技能"]], timeout: 10, failure: "The skills command chip did not appear.")
        XCTAssertTrue(app.buttons["压缩会话"].exists, "The compact command chip did not appear.")
        XCTAssertTrue(app.buttons["生成 AGENTS.md"].exists, "The init command chip did not appear.")
        XCTAssertTrue(app.buttons["会话目标"].exists, "The goal command chip did not appear.")

        let chips = app.scrollViews["commandPalette.chips"]
        for _ in 0..<4 {
            chips.swipeLeft()
        }
        usage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["会话用量"].waitForExistence(timeout: 8), "The usage sheet did not open.")
        let usageShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        usageShot.name = "RemoteCommandPalette-Usage"
        usageShot.lifetime = .keepAlways
        add(usageShot)
        app.buttons["关闭"].tap()

        chips.swipeLeft()
        skills.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["选择技能"].waitForExistence(timeout: 8), "The skills sheet did not open.")
        let skillsShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        skillsShot.name = "RemoteCommandPalette-Skills"
        skillsShot.lifetime = .keepAlways
        add(skillsShot)
        app.buttons["关闭"].tap()
        recordStep("command_palette_sheets_ready", since: workflowStartedAt)
    }

    private func waitForDirectoryLoadingToFinish(timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let loading = app.staticTexts["正在加载"]
            let loadingWorkspaces = app.staticTexts["正在加载工作区"]
            if !loading.exists && !loadingWorkspaces.exists { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    private func waitForConversationLoadingToFinish(timeout: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.18))
        let loading = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "正在加载")
        ).firstMatch
        guard loading.exists else { return }
        XCTAssertTrue(waitUntil(timeout: timeout) { !loading.exists }, "The conversation loading state did not finish.")
    }

    private func requireFirst(
        _ elements: [XCUIElement],
        timeout: TimeInterval,
        failure: String
    ) throws -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let element = elements.first(where: \.exists) { return element }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        if let element = elements.first(where: \.exists) {
            return element
        }
        recordDiagnostics(named: "RequiredElementMissing")
        XCTFail(failure)
        throw WorkflowError.requiredElementMissing
    }

    private func requireUsableElement(
        in query: XCUIElementQuery,
        timeout: TimeInterval,
        failure: String
    ) throws -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for index in 0..<query.count {
                let candidate = query.element(boundBy: index)
                if candidate.exists && candidate.isEnabled && candidate.isHittable { return candidate }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        recordDiagnostics(named: "UsableElementMissing")
        XCTFail(failure)
        throw WorkflowError.requiredElementMissing
    }

    private func tapEvenIfCovered(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func scrollToHittable(_ element: XCUIElement) -> Bool {
        guard waitUntil(timeout: 5, condition: { element.exists }) else { return false }
        for _ in 0..<8 {
            if element.isHittable { return true }
            app.swipeUp()
        }
        for _ in 0..<8 {
            if element.isHittable { return true }
            app.swipeDown()
        }
        return element.isHittable
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return condition()
    }

    private func uniqueIdentifiers(from query: XCUIElementQuery) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for index in 0..<query.count {
            let identifier = query.element(boundBy: index).identifier
            if !identifier.isEmpty, seen.insert(identifier).inserted { result.append(identifier) }
        }
        return result
    }

    private func recordStep(_ name: String, since started: Date) {
        let elapsedMS = Date().timeIntervalSince(started) * 1_000
        let totalMS = Date().timeIntervalSince(workflowStartedAt) * 1_000
        let line = String(format: "[IOS_E2E_PERF] step=%@ elapsed_ms=%.0f total_ms=%.0f", name, elapsedMS, totalMS)
        print(line)
        let attachment = XCTAttachment(string: line)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func recordDiagnostics(named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name)-Hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    private enum WorkflowError: Error {
        case requiredElementMissing
    }
}

/// Run on a fresh simulator installation so notification authorization is undecided.
final class NotificationOnboardingUITests: XCTestCase {
    func testLaterPersistsAcrossRelaunch() {
        let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
        app.launch()
        let prompt = app.alerts.firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 15))
        let later = app.buttons.matching(NSPredicate(format: "label IN %@", ["Later", "稍后"])).firstMatch
        XCTAssertTrue(later.exists)
        later.tap()
        XCTAssertFalse(prompt.exists)
        app.terminate()
        app.launch()
        let sidebar = app.buttons.matching(NSPredicate(format: "label IN %@", ["Open sidebar", "打开侧栏"])).firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 15))
        XCTAssertFalse(prompt.waitForExistence(timeout: 3), "Skipping onboarding must survive process restart.")
        // Use the existing settings inspection route without signing in a test account.
        app.terminate()
        app.launchArguments = ["--settings"]
        app.launch()
        let notifications = app.buttons["settings.notifications"]
        XCTAssertTrue(notifications.waitForExistence(timeout: 5))
        notifications.tap()
        let systemPrompt = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        XCTAssertTrue(systemPrompt.waitForExistence(timeout: 10), "Settings must still allow authorization after Later.")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "NotificationAuthorizationAfterLater"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

final class SidebarNavigationUITests: XCTestCase {
    func testNewChatOffersHarnessProfilesInCompactAndWideSidebar() {
        let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
        app.launchArguments = ["--harness-preview", "--drawer", "--simplified-chinese"]
        app.launchMobileReady()
        let later = app.alerts.buttons["稍后"]
        if later.waitForExistence(timeout: 3) { later.tap() }
        let newChat = app.buttons["sidebar.newChat"]
        XCTAssertTrue(newChat.waitForExistence(timeout: 10))
        XCTAssertTrue(newChat.isEnabled)
        XCTAssertTrue(newChat.label.contains("新聊天"))
        let workspace = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sidebar.workspace.")).firstMatch
        XCTAssertTrue(workspace.exists)
        workspace.tap()
        let compact = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        compact.name = "SidebarCompact"
        compact.lifetime = .keepAlways
        add(compact)
        newChat.tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "标准")).firstMatch.waitForExistence(timeout: 5))
        app.terminate()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launchMobileReady()
        XCTAssertTrue(newChat.waitForExistence(timeout: 10))
        XCTAssertTrue(newChat.isHittable)
        app.scrollViews["sidebar.workspaces"].swipeUp()
        XCTAssertLessThan(workspace.frame.maxY, newChat.frame.minY, "The final workspace must scroll clear of the floating actions.")
        let wide = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        wide.name = "SidebarWide"
        wide.lifetime = .keepAlways
        add(wide)
    }
}

final class GitHubLoginPresentationUITests: XCTestCase {
    func testLoginUsesCompactSheetAndOpensBrowserAutomatically() {
        let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
        app.launchArguments = ["--drawer", "--simplified-chinese"]
        app.launch()
        let later = app.alerts.buttons["稍后"]
        if later.waitForExistence(timeout: 3) { later.tap() }
        let account = app.buttons["使用 GitHub 登录"]
        XCTAssertTrue(account.waitForExistence(timeout: 10), "Run on a signed-out simulator.")
        account.tap()
        let login = app.buttons["account.login"]
        XCTAssertTrue(login.waitForExistence(timeout: 5))
        let title = app.staticTexts["使用 GitHub 登录"]
        XCTAssertGreaterThan(title.frame.minY, app.frame.height * 0.5)
        let sheet = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        sheet.name = "CompactGitHubLogin"
        sheet.lifetime = .keepAlways
        add(sheet)
        login.tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        let opened = XCTNSPredicateExpectation(predicate: NSPredicate(format: "state == %d", XCUIApplication.State.runningForeground.rawValue), object: safari)
        XCTAssertEqual(XCTWaiter.wait(for: [opened], timeout: 30), .completed, "A single login tap must open the authorization browser.")
        let browser = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        browser.name = "AutomaticallyOpenedAuthorization"
        browser.lifetime = .keepAlways
        add(browser)
        app.activate()
        XCTAssertTrue(login.waitForExistence(timeout: 5))
        XCTAssertTrue(login.isEnabled, "Returning from the browser must allow reopening the same authorization.")
        XCTAssertTrue(login.label.contains("打开 GitHub 授权"))
        app.terminate()
    }
}

final class MobileParityUITests: XCTestCase {
    func testAccountDevicePickerShowsTheDirectoryAndWaitsForTheHost() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
        app.launchArguments = ["--harness-preview", "--account-device-picker-preview", "--incompatible-device-preview", "--simplified-chinese"]
        app.launchMobileReady()
        let header = app.staticTexts["connect-account-device-title"]
        XCTAssertTrue(header.waitForExistence(timeout: 8))
        let first = app.buttons["connect-account-device-row-account-desktop-1"]
        XCTAssertTrue(first.label.contains("当前控制"))
        let offline = app.buttons["connect-account-device-row-account-desktop-3"]
        XCTAssertFalse(offline.isEnabled)
        let incompatible = app.buttons["connect-account-device-row-account-desktop-5"]
        XCTAssertFalse(incompatible.isEnabled)
        XCTAssertTrue(incompatible.label.contains("客户端版本不兼容，无法互控。"))
        let bottom = app.buttons["connect-account-device-row-account-desktop-9"]
        let before = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        before.name = "ConnectAccountDevices"
        before.lifetime = .keepAlways
        add(before)
        if !bottom.isHittable { app.swipeUp() }
        XCTAssertTrue(bottom.isHittable)
        if !first.isHittable { app.swipeDown() }
        let failure = app.buttons["connect-account-device-row-account-desktop-2"]
        failure.tap()
        XCTAssertTrue(header.exists)
        let retry = app.buttons["connect-account-device-refresh"]
        let failed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "重试"), object: retry)
        XCTAssertEqual(XCTWaiter.wait(for: [failed], timeout: 8), .completed)
        XCTAssertTrue(header.exists)
        XCTAssertTrue(failure.isEnabled)
        app.buttons["connect-account-device-row-account-desktop-4"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: header)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 8), .completed)
    }

    func testDeviceModelSettingsUseTheControlledDesktopAndShowCompatibleModels() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
        app.launchArguments = ["--harness-preview", "--device-model-defaults-preview", "--simplified-chinese"]
        app.launchMobileReady()
        let entry = app.buttons["device-model-settings"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        if !entry.isHittable { app.swipeUp() }
        entry.tap()
        let header = app.staticTexts["device-model-page"]
        XCTAssertTrue(header.waitForExistence(timeout: 8))
        XCTAssertEqual(header.label, "Account desktop 1")

        func capture(_ name: String) {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = name
            shot.lifetime = .keepAlways
            add(shot)
        }

        func assertCenteredPanel() {
            // The title starts after the leading 8-point inset and 48-point back control.
            let expectedLeft = app.frame.midX - 240 + 56
            XCTAssertEqual(header.frame.minX, expectedLeft, accuracy: 8)
        }

        if UIDevice.current.userInterfaceIdiom == .pad { assertCenteredPanel() }
        capture("DeviceModelDefaults")
        let imageRole = app.buttons["device-model-role-image_understanding"]
        XCTAssertTrue(imageRole.exists)
        imageRole.tap()
        let image = app.buttons["device-model-option-vision"]
        XCTAssertTrue(image.waitForExistence(timeout: 8))
        XCTAssertEqual(header.label, "多模态模型")
        XCTAssertFalse(app.buttons["device-model-option-mini"].exists)
        capture("DeviceModelMultimodal")
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCUIDevice.shared.orientation = .landscapeLeft
            let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.frame.width > app.frame.height
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 15), .completed)
            XCTAssertTrue(image.waitForExistence(timeout: 8))
            XCTAssertEqual(header.label, "多模态模型")
            assertCenteredPanel()
            capture("DeviceModelLandscape")
            XCUIDevice.shared.orientation = .portrait
            let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.frame.height > app.frame.width
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 15), .completed)
            XCTAssertTrue(image.waitForExistence(timeout: 8))
            XCTAssertEqual(header.label, "多模态模型")
        }
        image.tap()
        XCTAssertEqual(header.label, "Account desktop 1")
        XCTAssertTrue(imageRole.label.contains("vision-preview"))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "已更新为 vision-preview")).firstMatch.exists)
        imageRole.tap()
        app.buttons["device-model-option-unset"].tap()
        XCTAssertTrue(imageRole.label.contains("未配置"))
    }

    func testFilePreviewPresentsDownloadExporterAbovePreview() {
        let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
        app.launchArguments = ["--harness-preview", "--file-preview", "--download-preview", "--simplified-chinese"]
        app.launchMobileReady()
        let save = app.buttons.matching(NSPredicate(format: "label IN %@", ["存储", "保存", "Save"])).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 15))
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "FilePreviewDownloadExporter"
        evidence.lifetime = .keepAlways
        add(evidence)
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "Cancel"])).firstMatch
        if !cancel.exists {
            let locations = app.buttons["BackButton"]
            XCTAssertTrue(locations.exists); locations.tap()
        }
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
        let code = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "fn main()")).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 10))
    }

    func testPlanCardExplainsUnsupportedHost() {
        let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
        app.launchArguments = ["--harness-preview", "--plan-preview", "--simplified-chinese"]
        app.launchMobileReady()
        XCTAssertTrue(app.staticTexts["Mobile parity"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["查看计划"].exists)
        XCTAssertFalse(app.buttons["执行计划"].isEnabled)
        XCTAssertTrue(app.staticTexts["此电脑暂不支持执行计划"].exists)
        let evidence = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        evidence.name = "PlanCardUnsupportedHost"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    func testRemoteCodePreviewShowsNumberedLines() {
        let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
        app.launchArguments = ["--harness-preview", "--file-preview", "--simplified-chinese"]
        app.launchMobileReady()
        let code = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "fn main()")).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 10))
        XCTAssertTrue(code.label.trimmingCharacters(in: .whitespaces).hasPrefix("2"))
        let evidence = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        evidence.name = "NumberedCodePreview"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    func testLanguageSwitchUpdatesExistingAndNewScreens() {
        let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
        app.launchArguments = ["--harness-preview", "--settings", "--simplified-chinese"]
        app.launchMobileReady()
        let language = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "语言")).firstMatch
        XCTAssertTrue(language.waitForExistence(timeout: 15))
        language.tap()
        XCTAssertTrue(app.buttons["English"].waitForExistence(timeout: 5))
        app.buttons["English"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        let account = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Current account")).firstMatch
        XCTAssertTrue(account.exists)
        account.tap()
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 5))
        let evidence = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        evidence.name = "LanguageEnglishApplied"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    func testSignedOutWelcomeAndMiniAppsEntry() throws {
        let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
        app.launchArguments = ["--simplified-chinese"]
        app.launchMobileReady()
        let explore = app.buttons["探索小应用"]
        guard explore.waitForExistence(timeout: 10) else {
            throw XCTSkip("Uses a signed-out simulator installation.")
        }
        XCTAssertTrue(app.buttons["展开侧边栏"].isHittable)
        let evidence = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        evidence.name = "WelcomeHome"
        evidence.lifetime = .keepAlways
        add(evidence)
        explore.tap()
        XCTAssertTrue(app.buttons["miniapp-view-toggle"].waitForExistence(timeout: 10))
    }

    func testLocalGenUiWithFixtureProvider() throws {
        let app = try launchLocalGenUiFixture()
        let draft = app.textViews["local-genui-composer"]
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        draft.tap()
        draft.typeText("Create a focus timer")
        app.buttons["发送"].tap()

        let appBody = app.webViews.staticTexts["三端创作核对"].firstMatch
        XCTAssertTrue(appBody.waitForExistence(timeout: 30), "The native document must render the tool result.")
        let actions = app.buttons["小应用操作"]
        XCTAssertTrue(actions.waitForExistence(timeout: 12), "The local renderer must verify the final document.")
        XCTAssertTrue(app.webViews.staticTexts["同一份 OpenUI 文档"].exists)
        let evidence = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        evidence.name = "LocalGenUI-GeneratedDocument"
        evidence.lifetime = .keepAlways
        add(evidence)

        actions.tap()
        app.buttons["添加到小应用"].tap()
        app.buttons["返回"].firstMatch.tap()
        XCTAssertTrue(app.buttons["三端创作核对"].waitForExistence(timeout: 10))
    }

    func testLocalGenUiTranscriptCardsTimesAndCopyFormats() throws {
        let app = try launchLocalGenUiFixture()
        let input = app.textViews["local-genui-composer"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("TranscriptParityFixture")
        app.buttons["发送"].tap()

        let appMenu = app.buttons["小应用操作"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 30))
        app.buttons["返回"].firstMatch.tap()
        let card = app.buttons["三端会话卡片核对"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertEqual(card.value as? String, "可以使用")
        XCTAssertEqual(app.staticTexts.matching(identifier: "local-genui-message-time").count, 2)
        let transcript = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        transcript.name = "GenUI-Transcript"
        transcript.lifetime = .keepAlways
        add(transcript)

        let copy = app.buttons["local-genui-message-copy"].firstMatch
        copy.tap()
        XCTAssertTrue(app.buttons["复制（富文本）"].exists)
        XCTAssertTrue(app.buttons["复制纯文本"].exists)
        let markdown = app.buttons["复制 Markdown"]
        XCTAssertTrue(markdown.exists)
        let menu = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        menu.name = "GenUI-CopyFormats"
        menu.lifetime = .keepAlways
        add(menu)
        markdown.tap()
        card.tap()
        XCTAssertTrue(appMenu.waitForExistence(timeout: 10))
    }

    func testLocalGenUiLongMessagePreservesDraftAndTranscriptPosition() throws {
        let app = try launchLocalGenUiFixture()
        let input = app.textViews["local-genui-composer"]
        let transcript = app.scrollViews["local-genui-transcript"]
        let sent = "LongMessageParityFixture "
            + String(repeating: "Keep this exact wording for the local conversation. ", count: 10)
            + "LongMessageEnd"
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText(sent)
        XCTAssertEqual(input.value as? String, sent)
        app.buttons["发送"].tap()
        XCTAssertTrue(app.buttons["小应用操作"].waitForExistence(timeout: 30))
        app.buttons["返回"].firstMatch.tap()

        input.tap()
        input.typeText("DraftBeforeFullText")
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            let start = transcript.coordinate(withNormalizedOffset: CGVector(dx: 0.38, dy: 0.32))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.38, dy: 0.86))
            start.press(forDuration: 0.08, thenDragTo: end)
            let gone = NSPredicate { _, _ in !keyboard.exists }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: nil)], timeout: 5), .completed)
        }
        let preview = app.staticTexts["local-genui-truncated-message"].firstMatch
        let link = app.links["全文"].firstMatch
        for _ in 0..<8 {
            if link.isHittable && link.frame.maxY < input.frame.minY { break }
            transcript.swipeDown()
        }
        XCTAssertTrue(preview.isHittable)
        XCTAssertFalse(preview.label.contains("LongMessageEnd"))
        XCTAssertTrue(link.isHittable)
        XCTAssertLessThan(link.frame.maxY, input.frame.minY)
        let before = preview.frame
        let shortened = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shortened.name = "GenUI-LongMessagePreview"
        shortened.lifetime = .keepAlways
        add(shortened)

        link.tap()
        let fullText = app.staticTexts["local-genui-full-text-content"]
        XCTAssertTrue(fullText.waitForExistence(timeout: 10))
        XCTAssertEqual(fullText.label, sent)
        let sheet = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        sheet.name = "GenUI-FullMessage"
        sheet.lifetime = .keepAlways
        add(sheet)
        app.buttons["关闭"].firstMatch.tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertEqual(preview.frame.minY, before.minY, accuracy: 40)
        XCTAssertEqual(input.value as? String, "DraftBeforeFullText")
    }

    func testLocalGenUiStreamingPreservesReadingPositionThenFollowsNewTurn() throws {
        let app = try launchLocalGenUiFixture()
        let input = app.textViews["local-genui-composer"]
        let transcript = app.scrollViews["local-genui-transcript"]
        let send = app.buttons["发送"]
        let stop = app.buttons["停止"]
        let oldestPrompt = "ScrollFollowSeed original reading position"
        let oldest = app.staticTexts[oldestPrompt]
        let seedTail = app.staticTexts["ScrollSeedTail"]
        let streamTail = app.staticTexts["ScrollStreamTail"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))

        func submit(_ text: String) {
            input.tap()
            input.typeText(text)
            send.tap()
        }

        func visible(_ element: XCUIElement) -> Bool {
            element.isHittable && element.frame.maxY < input.frame.minY &&
                element.frame.minY > transcript.frame.minY
        }

        func waitUntilVisible(_ element: XCUIElement) {
            let predicate = NSPredicate { _, _ in visible(element) }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)],
                                          timeout: 10), .completed)
        }

        submit(oldestPrompt)
        waitUntilVisible(seedTail)
        XCTAssertFalse(visible(oldest))

        submit("ScrollFollowStreamFixture")
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        for _ in 0..<6 {
            if visible(oldest) { break }
            transcript.swipeDown()
        }
        XCTAssertTrue(visible(oldest))
        XCTAssertTrue(stop.exists, "The transcript must be scrolled before the reply finishes.")
        let position = oldest.frame.minY
        XCTAssertTrue(send.waitForExistence(timeout: 25))
        XCTAssertTrue(visible(oldest))
        XCTAssertEqual(oldest.frame.minY, position, accuracy: 30)
        XCTAssertFalse(visible(streamTail))

        submit("ScrollFollowResume")
        waitUntilVisible(app.staticTexts["ScrollResumeTail"])
        XCTAssertFalse(visible(oldest))
    }

    func testMissingGeneratedMiniAppShortcutShowsUnavailablePage() throws {
        guard #available(iOS 16.4, *) else { throw XCTSkip("URL launch requires iOS 16.4.") }
        let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
        app.launchArguments = ["--harness-preview", "--drawer", "--simplified-chinese"]
        app.launchMobileReady()
        let missing = URL(string: "openbitfun://miniapp/local-genui:00000000-0000-4000-8000-f00000000001")!
        app.open(missing)

        let status = app.staticTexts["local-genui-app-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "找不到这个应用了。")
        XCTAssertFalse(app.webViews.firstMatch.exists)
        XCTAssertFalse(app.buttons["小应用操作"].exists)
        let evidence = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        evidence.name = "MissingGeneratedMiniAppShortcut"
        evidence.lifetime = .keepAlways
        add(evidence)

        app.buttons["返回"].tap()
        XCTAssertTrue(status.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["miniapp-view-toggle"].exists)
    }

    func testLocalGenUiGalleryReturnsToItsOwningConversation() throws {
        let app = try launchLocalGenUiFixture()
        let input = app.textViews["local-genui-composer"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("GalleryReturnParity")
        app.buttons["发送"].tap()

        let actions = app.buttons["小应用操作"]
        XCTAssertTrue(actions.waitForExistence(timeout: 30))
        actions.tap()
        app.buttons["添加到小应用"].tap()
        for _ in 0..<3 { app.buttons["返回"].firstMatch.tap() }

        let sidebarEntry = app.buttons["小应用"].firstMatch
        if !sidebarEntry.isHittable { app.buttons["展开侧边栏"].firstMatch.tap() }
        XCTAssertTrue(sidebarEntry.waitForExistence(timeout: 10))
        sidebarEntry.tap()
        let toggle = app.buttons["miniapp-view-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        if toggle.label == "切换为列表" { toggle.tap() }
        let card = app.buttons.matching(NSPredicate(format:
            "identifier BEGINSWITH %@ AND label CONTAINS %@", "miniapp:", "三端应用馆会话核对")).firstMatch
        for _ in 0..<6 {
            if card.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(card.isHittable)
        card.tap()
        XCTAssertTrue(actions.waitForExistence(timeout: 15))
        actions.tap()
        app.buttons["对话"].tap()
        XCTAssertTrue(app.staticTexts["GalleryReturnParity"].waitForExistence(timeout: 10))
        XCTAssertTrue(input.exists)
    }

    func testLocalGenUiGalleryUpdatesCoverAfterEditingFromGallery() throws {
        let app = try launchLocalGenUiFixture()
        let fixtureID = String(UUID().uuidString.prefix(6))
        let title = "三端封面核对 \(fixtureID)"
        let input = app.textViews["local-genui-composer"]
        let actions = app.buttons["小应用操作"]

        func submit(_ operation: String, content: String) {
            XCTAssertTrue(input.waitForExistence(timeout: 10))
            input.tap()
            input.typeText("ThumbnailParity\(operation)\(fixtureID)")
            app.buttons["发送"].tap()
            XCTAssertTrue(actions.waitForExistence(timeout: 30))
            XCTAssertTrue(app.webViews.firstMatch.staticTexts[content].waitForExistence(timeout: 10))
        }

        func back(times: Int) {
            for _ in 0..<times { app.buttons["返回"].firstMatch.tap() }
        }

        submit("Create", content: "初始封面")
        actions.tap()
        app.buttons["添加到小应用"].tap()
        back(times: 3)

        let entry = app.buttons["小应用"].firstMatch
        if !entry.isHittable { app.buttons["展开侧边栏"].firstMatch.tap() }
        entry.tap()
        let toggle = app.buttons["miniapp-view-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        if toggle.label == "切换为列表" { toggle.tap() }
        let card = app.buttons.matching(NSPredicate(format:
            "identifier BEGINSWITH %@ AND label CONTAINS %@", "miniapp:", title)).firstMatch
        for _ in 0..<10 {
            if card.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(card.isHittable)
        let before = card.screenshot()
        card.tap()
        XCTAssertTrue(actions.waitForExistence(timeout: 15))
        actions.tap()
        app.buttons["对话"].tap()

        submit("Update", content: "更新后的封面")
        back(times: 3)
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            card.isHittable && card.screenshot().pngRepresentation != before.pngRepresentation
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 10), .completed)
        for (name, screenshot) in [("GenUiGalleryCoverBefore", before), ("GenUiGalleryCoverAfter", card.screenshot())] {
            let evidence = XCTAttachment(screenshot: screenshot)
            evidence.name = name
            evidence.lifetime = .keepAlways
            add(evidence)
        }
    }

    func testLocalGenUiGalleryUsesAdditionOrderAfterRestart() throws {
        let app = try launchLocalGenUiFixture()
        let firstID = String(UUID().uuidString.prefix(6))
        let secondID = String(UUID().uuidString.prefix(6))
        let firstTitle = "三端封面核对 \(firstID)"
        let secondTitle = "三端封面核对 \(secondID)"
        let composer = app.textViews["local-genui-composer"]
        let actions = app.buttons["小应用操作"]
        let back = app.buttons["返回"].firstMatch

        func create(_ id: String) {
            XCTAssertTrue(composer.waitForExistence(timeout: 10))
            composer.tap()
            composer.typeText("ThumbnailParityCreate\(id)")
            app.buttons["发送"].tap()
            XCTAssertTrue(actions.waitForExistence(timeout: 30))
        }

        func addToGallery() {
            actions.tap()
            app.buttons["添加到小应用"].tap()
        }

        func verifyGallery(_ screenshotName: String) {
            let entry = app.buttons["小应用"].firstMatch
            if !entry.isHittable { app.buttons["展开侧边栏"].firstMatch.tap() }
            XCTAssertTrue(entry.waitForExistence(timeout: 10))
            entry.tap()
            let toggle = app.buttons["miniapp-view-toggle"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 10))
            if toggle.label == "切换为列表" { toggle.tap() }

            func card(_ title: String) -> XCUIElement {
                app.buttons.matching(NSPredicate(format:
                    "identifier BEGINSWITH %@ AND label CONTAINS %@", "miniapp:", title)).firstMatch
            }
            let first = card(firstTitle)
            let second = card(secondTitle)
            for _ in 0..<5 {
                if first.isHittable && second.isHittable { break }
                app.scrollViews.firstMatch.swipeUp()
            }
            XCTAssertTrue(first.isHittable && second.isHittable)
            XCTAssertTrue(first.label.contains("AI 生成的小应用"))
            XCTAssertTrue(second.label.contains("AI 生成的小应用"))
            let firstRow = first.frame.minY
            let secondRow = second.frame.minY
            XCTAssertTrue(firstRow < secondRow || (firstRow == secondRow && first.frame.minX < second.frame.minX))
            let evidence = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            evidence.name = screenshotName
            evidence.lifetime = .keepAlways
            add(evidence)
        }

        create(firstID)
        back.tap()
        back.tap()
        app.buttons["local-genui-new-session"].tap()
        create(secondID)
        addToGallery()
        back.tap()
        back.tap()

        let olderSession = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", firstTitle)).firstMatch
        XCTAssertTrue(olderSession.waitForExistence(timeout: 10))
        olderSession.tap()
        let olderApp = app.buttons[firstTitle]
        XCTAssertTrue(olderApp.waitForExistence(timeout: 10))
        olderApp.tap()
        XCTAssertTrue(actions.waitForExistence(timeout: 15))
        addToGallery()
        for _ in 0..<3 { back.tap() }
        verifyGallery("GenUiGalleryAdditionOrder")

        app.terminate()
        app.launchMobileReady()
        verifyGallery("GenUiGalleryAdditionOrderAfterRestart")
    }

    func testLocalGenUiCalendarActions() throws {
        let app = try launchLocalGenUiFixture()
        let draft = app.textViews["local-genui-composer"]
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        draft.tap()
        draft.typeText("Verify calendar actions")
        app.buttons["发送"].tap()

        let web = app.webViews.firstMatch
        XCTAssertTrue(app.buttons["小应用操作"].waitForExistence(timeout: 30))
        let query = web.buttons["查询测试日程"]
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        query.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let access = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["Allow Full Access", "允许完全访问"])).firstMatch
        let count = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "找到 ")).firstMatch
        if !count.waitForExistence(timeout: 2), access.waitForExistence(timeout: 4) { access.tap() }
        XCTAssertTrue(count.waitForExistence(timeout: 7))
        let baseline = try XCTUnwrap(Int(String(count.label.filter(\.isNumber))))

        let create = web.buttons["添加测试日程"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()

        let created = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "已添加日程")).firstMatch
        XCTAssertTrue(created.waitForExistence(timeout: 7), "Calendar access must result in a real saved event.")
        let id = String(created.label.filter(\.isNumber))
        XCTAssertFalse(id.isEmpty)
        let field = web.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", ""), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 4), .completed)
        field.tap()
        field.typeText(id)
        XCTAssertEqual(field.value as? String, id)
        web.staticTexts["三端日历核对"].firstMatch.tap()

        web.buttons["更新测试日程"].tap()
        XCTAssertTrue(app.staticTexts["已更新日程（编号 \(id)）"].waitForExistence(timeout: 5))
        query.tap()
        XCTAssertTrue(app.staticTexts["找到 \(baseline + 1) 个日程"].waitForExistence(timeout: 5))
        let evidence = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        evidence.name = "LocalGenUI-CalendarCount"
        evidence.lifetime = .keepAlways
        add(evidence)

        web.buttons["删除测试日程"].tap()
        XCTAssertTrue(app.staticTexts["已删除日程（编号 \(id)）"].waitForExistence(timeout: 5))
        query.tap()
        XCTAssertTrue(app.staticTexts["找到 \(baseline) 个日程"].waitForExistence(timeout: 5))
    }

    func testLocalGenUiHostedImages() throws {
        let app = try launchLocalGenUiFixture()
        let draft = app.textViews["local-genui-composer"]
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        draft.tap()
        draft.typeText("PhotoParityFixture")
        app.buttons["发送"].tap()

        let web = app.webViews.firstMatch
        XCTAssertTrue(app.buttons["小应用操作"].waitForExistence(timeout: 30))
        XCTAssertTrue(web.staticTexts["三端图片核对"].firstMatch.exists)
        XCTAssertTrue(web.images["Tangerine"].firstMatch.waitForExistence(timeout: 24))
        let evidence = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        evidence.name = "LocalGenUI-HostedImages"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    func testLocalGenUiAnimatedCover() throws {
        let app = try launchLocalGenUiFixture()
        let draft = app.textViews["local-genui-composer"]
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        draft.tap()
        draft.typeText("MotionParityFixture")
        app.buttons["发送"].tap()

        XCTAssertTrue(app.buttons["小应用操作"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.webViews.staticTexts["三端动效核对"].firstMatch.exists)
    }

    func testLocalGenUiGestureScoreboardWithoutCamera() throws {
        let app = try launchLocalGenUiFixture()
        let draft = app.textViews["local-genui-composer"]
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        draft.tap()
        draft.typeText("GestureParityFixture")
        app.buttons["发送"].tap()

        let web = app.webViews.firstMatch
        XCTAssertTrue(app.buttons["小应用操作"].waitForExistence(timeout: 30))
        let toggle = web.switches["开启手势记分"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.tap()
        let unavailable = web.switches["此设备不支持手势识别"]
        XCTAssertTrue(unavailable.waitForExistence(timeout: 10))
        let manual = web.buttons["乙队 加 1 分"]
        XCTAssertTrue(manual.exists)
        manual.tap()
        XCTAssertTrue(web.staticTexts["1"].firstMatch.waitForExistence(timeout: 5))
        let evidence = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        evidence.name = "LocalGenUI-GestureScoreboardWithoutCamera"
        evidence.lifetime = .keepAlways
        add(evidence)

        unavailable.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["摄像头已开"].exists)
    }

    func testLocalGenUiCrossDeviceImage() throws {
        continueAfterFailure = false
        let app = try launchLocalGenUiFixture()
        let draft = app.textViews["local-genui-composer"]
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        draft.tap()
        draft.typeText("DeviceImageParityFixture")
        app.buttons["发送"].tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(app.buttons["小应用操作"].waitForExistence(timeout: 30))

        let imageKind = UserDefaults.standard.string(forKey: "OpenBitFunGenUiImageKind") ??
            ProcessInfo.processInfo.environment["OPENBITFUN_GENUI_IMAGE_KIND"] ??
            ProcessInfo.processInfo.environment["TEST_RUNNER_OPENBITFUN_GENUI_IMAGE_KIND"] ?? "gallery"
        let sourceButton = switch imageKind {
        case "photo": web.buttons["从其他设备拍照"]
        case "scan": web.buttons["从其他设备扫描文档"]
        default: web.buttons["选择其他设备的图片"]
        }
        XCTAssertTrue(sourceButton.waitForExistence(timeout: 10))
        sourceButton.tap()
        let nearby = ProcessInfo.processInfo.environment["OPENBITFUN_GENUI_LIVE_NEARBY"] == "1"
        if nearby {
            let peer = app.buttons["genui-nearby-device"].firstMatch
            XCTAssertTrue(peer.waitForExistence(timeout: 60))
            peer.tap()
            let verification = app.staticTexts["genui-nearby-verification"]
            XCTAssertTrue(verification.waitForExistence(timeout: 12))
            let comparison = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            comparison.name = "GenUiNearbyRequester"
            comparison.lifetime = .keepAlways
            add(comparison)
            app.buttons["验证码一致"].tap()
        } else {
            let fallback = app.buttons["使用连接码"]
            XCTAssertTrue(fallback.waitForExistence(timeout: 12))
            fallback.tap()
        }
        let copy = app.buttons["复制连接码"]
        if !nearby { XCTAssertTrue(copy.waitForExistence(timeout: 12)) }
        let transferred = web.images["从其他设备接收的图片"]

        if nearby || ProcessInfo.processInfo.environment["OPENBITFUN_GENUI_LIVE_IMAGE_TRANSFER"] == "1" {
            if !nearby { copy.tap() }
            if nearby {
                let failed = app.staticTexts["无法连接这台设备，请重试。"]
                let outcome = XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in transferred.exists || failed.exists }, object: nil
                )
                XCTAssertEqual(XCTWaiter.wait(for: [outcome], timeout: 100), .completed)
                XCTAssertTrue(transferred.exists, "The nearby sender must deliver its photo.")
            } else {
                XCTAssertTrue(transferred.waitForExistence(timeout: 100))
            }
            let dismissed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["genui-image-receive"]
            )
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)

            app.buttons["返回"].firstMatch.tap()
            let reopen = app.buttons["三端取材核对"].firstMatch
            XCTAssertTrue(reopen.waitForExistence(timeout: 10))
            reopen.tap()
            XCTAssertTrue(transferred.waitForExistence(timeout: 10), "The saved image must reopen with the document.")
        } else {
            app.buttons["关闭"].firstMatch.tap()
            XCTAssertTrue(sourceButton.waitForExistence(timeout: 5))
        }
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "LocalGenUI-CrossDeviceImage"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLocalGenUiCrossDevicePhoto() throws {
        UserDefaults.standard.set("photo", forKey: "OpenBitFunGenUiImageKind")
        defer { UserDefaults.standard.removeObject(forKey: "OpenBitFunGenUiImageKind") }
        try testLocalGenUiCrossDeviceImage()
    }

    func testLocalGenUiCrossDeviceScan() throws {
        UserDefaults.standard.set("scan", forKey: "OpenBitFunGenUiImageKind")
        defer { UserDefaults.standard.removeObject(forKey: "OpenBitFunGenUiImageKind") }
        try testLocalGenUiCrossDeviceImage()
    }

    func testLocalGenUiNearbySender() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["OPENBITFUN_GENUI_LIVE_NEARBY"] == "1" else {
            throw XCTSkip("Requires a second simulator running the GenUI image request.")
        }
        let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
        app.launchArguments = ["--harness-preview", "--drawer", "--simplified-chinese"]
        app.launchMobileReady()
        let entry = app.buttons["sidebar-local-bot"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        app.buttons["更多"].tap()
        app.buttons["发送图片到另一台设备"].tap()
        XCTAssertTrue(app.staticTexts["正在等待附近设备发来取材请求。"].waitForExistence(timeout: 12))
        let verification = app.staticTexts["genui-nearby-verification"]
        XCTAssertTrue(verification.waitForExistence(timeout: 100))
        let comparison = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        comparison.name = "GenUiNearbySender"
        comparison.lifetime = .keepAlways
        add(comparison)
        app.buttons["验证码一致"].tap()
        let gallery = app.buttons["从图库选择"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 12))
        gallery.tap()
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 15))
        photo.tap()
        let send = app.buttons["发送选中的图片"]
        XCTAssertTrue(send.waitForExistence(timeout: 12))
        send.tap()
        XCTAssertTrue(app.staticTexts["图片已送达。"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["正在等待附近设备发来取材请求。"].waitForExistence(timeout: 12))
        let delivered = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        delivered.name = "GenUiNearbyDelivered"
        delivered.lifetime = .keepAlways
        add(delivered)
    }

    func testLocalGenUiComposerKeepsTheKeyboardDuringModelSelection() throws {
        let app = try launchLocalGenUiFixture()
        let input = app.textViews["local-genui-composer"]
        let selector = app.buttons["local-genui-model-control"]
        let transcript = app.scrollViews["local-genui-transcript"]
        let keyboard = app.keyboards.firstMatch
        let manage = app.buttons["管理模型"]
        let draft = "ComposerParityDraft\nKeep the second line"
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        let restingHeight = input.frame.height
        let restingRowDistance = selector.frame.minY - input.frame.minY

        func capture(_ name: String) {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        func dismissKeyboard() {
            let start = transcript.coordinate(withNormalizedOffset: CGVector(dx: 0.38, dy: 0.32))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.38, dy: 0.86))
            start.press(forDuration: 0.08, thenDragTo: end)
            let dismissed = NSPredicate { _, _ in !keyboard.exists }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: dismissed, object: nil)],
                                          timeout: 8), .completed)
        }

        capture("GenUI-ComposerResting")
        input.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        input.typeText("ComposerParityDraft")
        XCTAssertGreaterThan(selector.frame.minY - input.frame.minY, restingRowDistance + 8)
        dismissKeyboard()
        XCTAssertEqual(selector.frame.minY - input.frame.minY, restingRowDistance, accuracy: 4)
        XCTAssertEqual(input.value as? String, "ComposerParityDraft")
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.45)).tap()
        input.typeText("\nKeep the second line")
        XCTAssertEqual(input.value as? String, draft)
        let editingHeight = input.frame.height
        XCTAssertGreaterThan(editingHeight, restingHeight + 10)
        XCTAssertEqual(editingHeight, 66, accuracy: 2)

        let selectedName = selector.label
        selector.tap()
        XCTAssertTrue(manage.waitForExistence(timeout: 8))
        XCTAssertTrue(keyboard.exists)
        XCTAssertLessThan(manage.frame.maxY, selector.frame.minY)
        capture("GenUI-ComposerModelMenu")
        let choices = app.buttons.matching(identifier: "local-genui-model-option").allElementsBoundByIndex
        let first = try XCTUnwrap(choices.first)
        XCTAssertEqual(first.label, selectedName)
        let choice = choices.dropFirst().first { $0.label != selectedName } ?? first
        let nextName = choice.label
        choice.tap()
        XCTAssertFalse(manage.exists)
        XCTAssertTrue(keyboard.exists)
        XCTAssertEqual(input.value as? String, draft)
        XCTAssertEqual(selector.label, nextName)

        dismissKeyboard()
        XCTAssertEqual(input.value as? String, draft)
        XCTAssertEqual(input.frame.height, editingHeight, accuracy: 4)
        capture("GenUI-ComposerMultilineResting")

        app.buttons["发送"].tap()
        XCTAssertTrue(app.buttons["小应用操作"].waitForExistence(timeout: 25))
    }

    func testLocalGenUiTextReplyKeepsTheEditorFocusedAfterAcceptingTheDraft() throws {
        let app = try launchLocalGenUiFixture()
        let input = app.textViews["local-genui-composer"]
        let keyboard = app.keyboards.firstMatch
        let send = app.buttons["发送"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        input.typeText("ScrollFollowResume")
        send.tap()

        XCTAssertTrue(app.staticTexts["ScrollResumeTail"].waitForExistence(timeout: 20))
        XCTAssertTrue(keyboard.exists)
        XCTAssertEqual(input.value as? String ?? "", "")
        let evidence = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        evidence.name = "GenUI-TextReplyContinuesEditing"
        evidence.lifetime = .keepAlways
        add(evidence)

        let nextDraft = "Continue with a fresh draft\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6"
        input.typeText(nextDraft)
        XCTAssertEqual(input.value as? String, nextDraft)
        XCTAssertEqual(input.frame.height, 114, accuracy: 2)
        let viewport = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        viewport.name = "GenUI-ComposerFourLineViewport"
        viewport.lifetime = .keepAlways
        add(viewport)
        send.tap()
        XCTAssertTrue(app.buttons["小应用操作"].waitForExistence(timeout: 25))
        XCTAssertFalse(keyboard.exists)
    }

    func testLocalGenUiModelPanelAdaptsWithoutLosingEditor() throws {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = try launchLocalGenUiFixture()
        let endpoint = try XCTUnwrap(ProcessInfo.processInfo.environment["OPENBITFUN_GENUI_FIXTURE_URL"])
        let compact = app.staticTexts["local-genui-model-bottom-sheet"]
        let centered = app.staticTexts["local-genui-model-centered"]
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        app.buttons["local-genui-model-control"].tap()
        app.buttons["管理模型"].tap()
        XCTAssertTrue((isPad ? centered : compact).waitForExistence(timeout: 8))
        try openGenUiAddModel(app)

        let display = app.textFields["genui-model-display"]
        let address = app.textFields["genui-model-url"]
        let model = app.textFields["genui-model-name"]
        let key = app.secureTextFields["genui-model-key"]
        let displayName = "Resize model probe"
        let testKey = "local-fixture-key"
        XCTAssertTrue(display.waitForExistence(timeout: 8))
        display.tap()
        display.typeText(displayName)
        address.tap()
        address.typeText(endpoint)
        key.tap()
        key.typeText(testKey)

        let modelScroll = app.scrollViews["local-genui-model-scroll"]
        let fetch = modelScroll.buttons["获取模型列表"]
        if !fetch.isHittable { modelScroll.swipeUp() }
        fetch.tap()
        let choice = modelScroll.buttons["parity-vision"]
        XCTAssertTrue(choice.waitForExistence(timeout: 15))
        if !choice.isHittable { modelScroll.swipeUp() }
        choice.tap()

        func verifyEditor(_ header: XCUIElement, _ name: String) {
            XCTAssertTrue(header.waitForExistence(timeout: 12))
            XCTAssertEqual(header.label, "添加模型")
            XCTAssertEqual(display.value as? String, displayName)
            XCTAssertEqual(address.value as? String, endpoint)
            XCTAssertEqual((key.value as? String)?.count, testKey.count)
            XCTAssertEqual(model.value as? String, "parity-vision")
            XCTAssertTrue(choice.exists)
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = name
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }

        verifyEditor(isPad ? centered : compact, "GenUI-ModelEditor-Portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 15), .completed)
        verifyEditor(centered, "GenUI-ModelEditor-Landscape")
        XCUIDevice.shared.orientation = .portrait
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.height > app.frame.width
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 15), .completed)
        verifyEditor(isPad ? centered : compact, "GenUI-ModelEditor-Restored")

        app.buttons["关闭"].tap()
        XCTAssertEqual((isPad ? centered : compact).label, "管理模型")
        XCTAssertFalse(app.staticTexts[displayName].exists)
        try openGenUiAddModel(app)
        XCTAssertNotEqual(display.value as? String, displayName)
        XCTAssertFalse(choice.exists)
    }

    func testLocalGenUiModelSheetKeepsDraftAndUsesDiscoveredModel() throws {
        let app = try launchLocalGenUiFixture()
        let endpoint = try XCTUnwrap(ProcessInfo.processInfo.environment["OPENBITFUN_GENUI_FIXTURE_URL"])
        let draft = app.textViews["local-genui-composer"]
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        draft.tap()
        let draftMarker = "Keep the draft while changing models"
        if (draft.value as? String)?.contains(draftMarker) != true {
            draft.typeText(draftMarker)
        }
        let enteredDraft = try XCTUnwrap(draft.value as? String)
        XCTAssertTrue(enteredDraft.contains(draftMarker))
        let selector = app.buttons["local-genui-model-control"]
        XCTAssertTrue(selector.waitForExistence(timeout: 10))
        selector.tap()
        app.buttons["管理模型"].tap()
        XCTAssertTrue(app.staticTexts["管理模型"].waitForExistence(timeout: 8))
        try openGenUiAddModel(app)

        let display = app.textFields["genui-model-display"]
        XCTAssertTrue(display.waitForExistence(timeout: 8))
        display.tap()
        display.typeText("Parity alternate")
        let address = app.textFields["genui-model-url"]
        address.tap()
        address.typeText(endpoint)
        let key = app.secureTextFields["genui-model-key"]
        key.tap()
        key.typeText("local-fixture-key")

        let modelScroll = app.scrollViews["local-genui-model-scroll"]
        let fetch = modelScroll.buttons["获取模型列表"]
        if !fetch.isHittable { modelScroll.swipeUp() }
        fetch.tap()
        let choice = modelScroll.buttons["parity-fast"]
        XCTAssertTrue(choice.waitForExistence(timeout: 15))
        if !choice.isHittable { modelScroll.swipeUp() }
        choice.tap()
        let field = app.textFields["genui-model-name"]
        XCTAssertEqual(field.value as? String, "parity-fast")
        let save = modelScroll.buttons["保存"]
        if !save.isHittable { modelScroll.swipeUp() }
        save.tap()
        XCTAssertTrue(app.staticTexts["当前使用"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Parity alternate"].firstMatch.exists)

        let list = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        list.name = "LocalGenUI-ModelProfiles"
        list.lifetime = .keepAlways
        add(list)

        let active = app.buttons["local-genui-active-profile"]
        XCTAssertTrue(active.waitForExistence(timeout: 8))
        active.tap()
        XCTAssertTrue(app.staticTexts["编辑模型"].waitForExistence(timeout: 8))
        fetch.tap()
        XCTAssertTrue(choice.waitForExistence(timeout: 15))
        XCTAssertEqual(field.value as? String, "parity-fast")
        let editor = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        editor.name = "LocalGenUI-ModelDiscovery"
        editor.lifetime = .keepAlways
        add(editor)
        app.buttons["关闭"].tap()
        XCTAssertTrue(app.staticTexts["管理模型"].waitForExistence(timeout: 8))
        app.buttons["关闭"].tap()
        XCTAssertTrue(selector.waitForExistence(timeout: 8))
        XCTAssertEqual(selector.label, "parity-fast")
        XCTAssertEqual(draft.value as? String, enteredDraft)

        app.buttons["发送"].tap()
        XCTAssertTrue(app.buttons["小应用操作"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.webViews.staticTexts["三端创作核对"].firstMatch.exists)
    }

    func testLocalGenUiCreationHistoryKeepsWorkingDraftAndSortsByActivity() throws {
        let app = try launchLocalGenUiFixture()
        let input = app.textViews["local-genui-composer"]
        let newSession = app.buttons["local-genui-new-session"]
        let rows = app.buttons.matching(identifier: "local-genui-session")
        let alpha = rows.matching(NSPredicate(format: "label CONTAINS %@", "三端记录甲")).firstMatch
        let beta = rows.matching(NSPredicate(format: "label CONTAINS %@", "三端记录乙")).firstMatch
        let back = app.buttons["返回"].firstMatch
        func send(_ prompt: String) {
            XCTAssertTrue(input.waitForExistence(timeout: 10))
            input.tap()
            input.typeText(prompt)
            app.buttons["发送"].tap()
        }
        func closeAppToHistory() {
            XCTAssertTrue(app.buttons["小应用操作"].waitForExistence(timeout: 30))
            back.tap()
            XCTAssertTrue(input.waitForExistence(timeout: 10))
            back.tap()
            XCTAssertTrue(newSession.waitForExistence(timeout: 10))
        }

        input.tap()
        input.typeText("Spare draft")
        back.tap()
        XCTAssertTrue(newSession.waitForExistence(timeout: 10))
        let baseline = rows.count
        newSession.tap()
        XCTAssertEqual(input.value as? String, "Spare draft")
        input.tap()
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Spare draft".count))
        back.tap()
        XCTAssertTrue(newSession.waitForExistence(timeout: 10))
        XCTAssertEqual(rows.count, baseline)

        newSession.tap()
        send("HistoryParityAlpha")
        closeAppToHistory()
        XCTAssertTrue(alpha.waitForExistence(timeout: 10))
        newSession.tap()
        send("HistoryParityBeta")
        closeAppToHistory()
        XCTAssertTrue(beta.waitForExistence(timeout: 10))
        XCTAssertLessThan(beta.frame.minY, alpha.frame.minY)
        XCTAssertNotNil(alpha.label.range(of: #"\d{4}.*\d{2}:\d{2}"#, options: .regularExpression))

        alpha.tap()
        send("HistoryParityAlphaFollowUp")
        back.tap()
        XCTAssertTrue(newSession.waitForExistence(timeout: 10))
        XCTAssertLessThan(alpha.frame.minY, beta.frame.minY)
        XCTAssertTrue(newSession.wait(for: \.isEnabled, toEqual: true, timeout: 20))
        let history = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        history.name = "LocalGenUI-CreationHistory"
        history.lifetime = .keepAlways
        add(history)

        alpha.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts.matching(identifier: "小应用已准备好。").count, 2)
        back.tap()
        XCTAssertTrue(newSession.waitForExistence(timeout: 10))

        beta.press(forDuration: 0.8)
        let delete = app.buttons["local-genui-delete-session"]
        XCTAssertTrue(delete.waitForExistence(timeout: 8))
        let menu = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        menu.name = "LocalGenUI-HistoryActions"
        menu.lifetime = .keepAlways
        add(menu)
        delete.tap()
        XCTAssertTrue(beta.wait(for: \.exists, toEqual: false, timeout: 10))
        XCTAssertTrue(alpha.exists)
    }

    func testLocalGenUiFirstValidationFailureCanBeReopenedAndCreatedAgain() throws {
        let app = try launchLocalGenUiFixture()
        let input = app.textViews["local-genui-composer"]
        let send = app.buttons["发送"]
        let actions = app.buttons["小应用操作"]
        let failure = app.staticTexts["没有生成成功"]
        let title = "三端首轮失败核对"
        let failedCards = app.buttons.matching(NSPredicate(format: "label == %@ AND value == %@", title, "没有生成成功"))
        let failedCard = failedCards.firstMatch
        let repairNotices = app.staticTexts.matching(identifier: "刚才的应用有点问题，正在自动修正")
        let readyCard = app.buttons.matching(NSPredicate(format: "label == %@ AND value == %@", title, "可以使用")).firstMatch

        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("FirstFailureParity")
        send.tap()
        XCTAssertTrue(failure.waitForExistence(timeout: 40))
        XCTAssertLessThan(failure.frame.midY, app.frame.height * 0.2)
        XCTAssertEqual(failure.frame.midY, app.buttons["返回"].firstMatch.frame.midY, accuracy: 8)
        XCTAssertFalse(actions.exists)
        XCTAssertFalse(app.webViews.firstMatch.exists)
        let rejected = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        rejected.name = "GenUI-FirstValidationFailure"
        rejected.lifetime = .keepAlways
        add(rejected)

        app.buttons["返回"].firstMatch.tap()
        XCTAssertTrue(failedCard.waitForExistence(timeout: 10))
        XCTAssertEqual(failedCards.count, 2)
        XCTAssertEqual(repairNotices.count, 1)
        let card = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        card.name = "GenUI-FailedCard"
        card.lifetime = .keepAlways
        add(card)
        app.terminate()
        app.launchMobileReady()
        XCTAssertTrue(app.buttons["sidebar-local-bot"].waitForExistence(timeout: 10))
        app.buttons["sidebar-local-bot"].tap()
        let session = app.buttons.matching(identifier: "local-genui-session")
            .matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        session.tap()
        XCTAssertTrue(failedCard.waitForExistence(timeout: 10))
        XCTAssertEqual(failedCards.count, 2)
        XCTAssertEqual(repairNotices.count, 1)
        let reopened = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        reopened.name = "GenUI-ReopenedRepairTranscript"
        reopened.lifetime = .keepAlways
        add(reopened)
        failedCard.tap()
        XCTAssertTrue(failure.waitForExistence(timeout: 10))
        XCTAssertFalse(actions.exists)

        app.buttons["返回"].firstMatch.tap()
        input.tap()
        input.typeText("FirstFailureParityRecover")
        send.tap()
        XCTAssertTrue(actions.waitForExistence(timeout: 35))
        XCTAssertTrue(app.webViews.staticTexts["同一应用修正后可使用"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["返回"].firstMatch.tap()
        XCTAssertTrue(readyCard.waitForExistence(timeout: 10))
        XCTAssertEqual(failedCards.count, 2)
        XCTAssertEqual(repairNotices.count, 1)
    }

    func testLocalGenUiRepairsFailedRenderAndKeepsThePreviousWorkingState() throws {
        let app = try launchLocalGenUiFixture()
        let input = app.textViews["local-genui-composer"]
        let web = app.webViews.firstMatch
        let ready = app.buttons["小应用操作"]
        let repairNotices = app.staticTexts.matching(identifier: "刚才的应用有点问题，正在自动修正")
        func send(_ prompt: String) {
            XCTAssertTrue(input.waitForExistence(timeout: 10))
            input.tap()
            input.typeText(prompt)
            XCTAssertEqual(input.value as? String, prompt)
            app.buttons["发送"].tap()
        }

        send("RepairParityCreate")
        XCTAssertTrue(app.staticTexts["正在自动修正…"].waitForExistence(timeout: 20))
        XCTAssertTrue(ready.waitForExistence(timeout: 30))
        XCTAssertTrue(web.staticTexts["自动修复已完成"].exists)
        XCTAssertTrue(web.staticTexts["保留原有区块"].exists)
        web.buttons["计数加一"].tap()
        XCTAssertTrue(web.staticTexts["保留计数 1"].waitForExistence(timeout: 10))

        app.buttons["返回"].firstMatch.tap()
        XCTAssertEqual(repairNotices.count, 1)
        send("RepairParityReject")
        XCTAssertTrue(app.staticTexts["正在自动修正…"].waitForExistence(timeout: 20))
        XCTAssertTrue(ready.waitForExistence(timeout: 30))
        XCTAssertTrue(web.staticTexts["自动修复已完成"].exists)
        XCTAssertTrue(web.staticTexts["保留计数 1"].exists)

        app.buttons["返回"].firstMatch.tap()
        XCTAssertEqual(repairNotices.count, 2)
        let transcript = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        transcript.name = "GenUI-RepairFallbackTranscript"
        transcript.lifetime = .keepAlways
        add(transcript)
        let readyCards = app.buttons.matching(NSPredicate(format: "label == %@ AND value == %@", "三端修复核对", "可以使用"))
        XCTAssertEqual(readyCards.count, 3)
        let latestCard = readyCards.element(boundBy: 2)
        XCTAssertTrue(latestCard.isHittable)
        latestCard.tap()
        XCTAssertTrue(web.staticTexts["保留计数 1"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "LocalGenUI-RepairKeptWorkingRevision"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["返回"].firstMatch.tap()
        send("RepairParityMigration")
        XCTAssertTrue(app.staticTexts["新版本和已有数据不兼容，已保留原来的版本"].waitForExistence(timeout: 30))
        XCTAssertTrue(web.staticTexts["保留计数 1"].exists)
        let migration = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        migration.name = "LocalGenUI-IncompatibleState"
        migration.lifetime = .keepAlways
        add(migration)
    }

    func testLocalGenUiFloatingControlsRespectLandscapeSafeAreas() throws {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = try launchLocalGenUiFixture()
        let input = app.textViews["local-genui-composer"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("InsetsParityLandscape")
        app.buttons["发送"].tap()

        let options = app.buttons["小应用操作"]
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(options.waitForExistence(timeout: 20))
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 24), .completed)
        let back = app.buttons["返回"].firstMatch
        XCTAssertTrue(options.waitForExistence(timeout: 10))
        let web = app.webViews.firstMatch
        let count = web.staticTexts["窗口计数 1"]
        web.buttons["窗口计数加一"].tap()
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        let viewport = app.frame
        let leading = back.frame.minX - viewport.minX
        let trailing = viewport.maxX - options.frame.maxX
        XCTAssertEqual(back.frame.size.width, 40, accuracy: 1)
        XCTAssertEqual(options.frame.size.width, 40, accuracy: 1)
        XCTAssertEqual(back.frame.midY, options.frame.midY, accuracy: 1)
        XCTAssertGreaterThanOrEqual(leading, 11)
        XCTAssertGreaterThanOrEqual(trailing, 11)
        XCTAssertGreaterThan(count.frame.minX, back.frame.minX)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "LocalGenUI-LandscapeSafeAreas"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let measurements = XCTAttachment(string: "Window \(viewport)\nBack \(back.frame)\nOptions \(options.frame)\nDocument \(count.frame)")
        measurements.name = "LocalGenUI-LandscapeMeasurements"
        measurements.lifetime = .keepAlways
        add(measurements)
        back.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 10))
    }

    func testLocalGenUiResumesVerificationAfterProcessTermination() throws {
        let app = try launchLocalGenUiFixture()
        let launchArguments = app.launchArguments
        let input = app.textViews["local-genui-composer"]
        let web = app.webViews.firstMatch
        let appCard = app.buttons.matching(identifier: "三端恢复核对")
        let pendingCard = appCard.matching(NSPredicate(format: "value == %@", "正在准备")).firstMatch
        func send(_ prompt: String) {
            XCTAssertTrue(input.waitForExistence(timeout: 10))
            input.tap()
            input.typeText(prompt)
            XCTAssertEqual(input.value as? String, prompt)
            app.buttons["发送"].tap()
        }
        func openSession() {
            app.buttons["sidebar-local-bot"].tap()
            let session = app.buttons.matching(identifier: "local-genui-session")
                .matching(NSPredicate(format: "label CONTAINS %@", "三端恢复核对")).firstMatch
            XCTAssertTrue(session.waitForExistence(timeout: 10))
            session.tap()
        }
        func attach(_ name: String) {
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = name
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }

        send("CheckpointParityBase")
        XCTAssertTrue(app.buttons["小应用操作"].waitForExistence(timeout: 30))
        XCTAssertTrue(web.staticTexts["原有版本"].exists)
        web.buttons["计数加一"].tap()
        XCTAssertTrue(web.staticTexts["保留计数 1"].waitForExistence(timeout: 10))

        app.terminate()
        app.launchArguments = launchArguments + ["--hold-genui-reopen-for-testing"]
        app.launchMobileReady()
        openSession()
        send("CheckpointParityUpdate")
        let checkpoint = app.descendants(matching: .any)["local-genui-review-checkpoint"].firstMatch
        XCTAssertTrue(checkpoint.waitForExistence(timeout: 20))
        attach("LocalGenUI-CheckpointBeforeExit")
        app.buttons["返回"].firstMatch.tap()
        XCTAssertTrue(pendingCard.waitForExistence(timeout: 4))
        XCTAssertEqual(appCard.count, 2)
        attach("LocalGenUI-PreparingCandidateCard")

        app.terminate()
        app.launchArguments = launchArguments
        app.launchMobileReady()
        openSession()
        XCTAssertTrue(appCard.firstMatch.waitForExistence(timeout: 10))
        appCard.firstMatch.tap()
        XCTAssertTrue(web.staticTexts["中断后恢复的版本"].waitForExistence(timeout: 20))
        XCTAssertTrue(web.staticTexts["保留计数 1"].exists)
        attach("LocalGenUI-RecoveredCheckpoint")

        app.buttons["返回"].firstMatch.tap()
        XCTAssertEqual(appCard.count, 2)
        XCTAssertFalse(pendingCard.exists)

        let rename = app.buttons["local-genui-rename-session"]
        XCTAssertTrue(rename.waitForExistence(timeout: 10))
        rename.tap()
        let titleEditor = app.textFields["conversation-rename-title"]
        XCTAssertTrue(titleEditor.waitForExistence(timeout: 10))
        attach("LocalGenUI-InlineRename")
        titleEditor.tap()
        let oldTitle = try XCTUnwrap(titleEditor.value as? String)
        titleEditor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldTitle.count))
        titleEditor.typeText("Checkpoint renamed")
        app.buttons["保存"].tap()
        XCTAssertEqual(rename.value as? String, "Checkpoint renamed")
        let actions = app.buttons["local-genui-session-actions"]
        actions.tap()
        let history = app.buttons["创作记录"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        attach("LocalGenUI-CreationHistoryAction")
        history.tap()
        let renamedSession = app.buttons.matching(identifier: "local-genui-session")
            .matching(NSPredicate(format: "label CONTAINS %@", "Checkpoint renamed")).firstMatch
        XCTAssertTrue(renamedSession.waitForExistence(timeout: 10))
        renamedSession.tap()
        XCTAssertEqual(rename.value as? String, "Checkpoint renamed")
    }

    func testLocalGenUiReopenProbeTimeoutKeepsAppAndUserData() throws {
        let app = try launchLocalGenUiFixture(arguments: ["--hold-genui-reopen-for-testing"])
        let input = app.textViews["local-genui-composer"]
        let web = app.webViews.firstMatch
        let ready = app.buttons["小应用操作"]
        let checkpoint = app.descendants(matching: .any)["local-genui-review-checkpoint"].firstMatch
        func send(_ prompt: String, openFromCandidate: Bool = false) {
            XCTAssertTrue(input.waitForExistence(timeout: 10))
            input.tap()
            input.typeText(prompt)
            app.buttons["发送"].tap()
            XCTAssertTrue(checkpoint.waitForExistence(timeout: 20))
            if openFromCandidate {
                app.buttons["返回"].firstMatch.tap()
                let pending = app.buttons.matching(NSPredicate(format: "label == %@ AND value == %@", "三端恢复核对", "正在准备")).firstMatch
                XCTAssertTrue(pending.waitForExistence(timeout: 4))
                pending.tap()
            }
            XCTAssertTrue(ready.waitForExistence(timeout: 20))
        }
        func attach(_ name: String) {
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = name
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }

        send("CheckpointParityBase", openFromCandidate: true)
        XCTAssertTrue(web.staticTexts["原有版本"].waitForExistence(timeout: 10))
        web.buttons["计数加一"].tap()
        XCTAssertTrue(web.staticTexts["保留计数 1"].waitForExistence(timeout: 10))
        app.buttons["返回"].firstMatch.tap()
        send("CheckpointParityUpdate")
        XCTAssertTrue(web.staticTexts["中断后恢复的版本"].waitForExistence(timeout: 10))
        XCTAssertTrue(web.staticTexts["保留计数 1"].exists)
        attach("LocalGenUI-ReopenProbeTimeoutApp")

        app.terminate()
        app.launchArguments.removeAll { $0 == "--hold-genui-reopen-for-testing" }
        app.launchMobileReady()
        app.buttons["sidebar-local-bot"].tap()
        let session = app.buttons.matching(identifier: "local-genui-session")
            .matching(NSPredicate(format: "label CONTAINS %@", "三端恢复核对")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        session.tap()
        let cards = app.buttons.matching(identifier: "三端恢复核对")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(cards.firstMatch.value as? String, "可以使用")
        attach("LocalGenUI-ReopenProbeTimeoutCards")
        cards.firstMatch.tap()
        XCTAssertTrue(web.staticTexts["中断后恢复的版本"].waitForExistence(timeout: 10))
        XCTAssertTrue(web.staticTexts["保留计数 1"].exists)
    }

    private func launchLocalGenUiFixture(arguments: [String] = []) throws -> XCUIApplication {
        guard let endpoint = ProcessInfo.processInfo.environment["OPENBITFUN_GENUI_FIXTURE_URL"] else {
            throw XCTSkip("Set OPENBITFUN_GENUI_FIXTURE_URL for the local model fixture.")
        }
        let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
        app.launchArguments = ["--harness-preview", "--drawer", "--simplified-chinese"] + arguments
        app.launchMobileReady()

        let entry = app.buttons["sidebar-local-bot"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        app.buttons["local-genui-new-session"].tap()
        let selector = app.buttons["local-genui-model-control"]
        XCTAssertTrue(selector.waitForExistence(timeout: 10))
        if selector.label == "配置模型" {
            selector.tap()
            let name = app.textFields["genui-model-display"]
            XCTAssertTrue(name.waitForExistence(timeout: 10))
            name.tap()
            name.typeText("Parity fixture")
            let address = app.textFields["genui-model-url"]
            address.tap()
            address.typeText(endpoint)
            let model = app.textFields["genui-model-name"]
            model.tap()
            model.typeText("parity-fixture")
            let key = app.secureTextFields["genui-model-key"]
            key.tap()
            key.typeText("local-fixture-key")
            app.buttons["保存并使用"].tap()
        }
        return app
    }

    private func openGenUiAddModel(_ app: XCUIApplication) throws {
        let scroll = app.scrollViews["local-genui-model-scroll"]
        let add = app.buttons["local-genui-model-add"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 8))
        for _ in 0..<6 {
            if add.isHittable && scroll.frame.contains(add.frame) { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(add.isHittable)
        XCTAssertTrue(scroll.frame.contains(add.frame))
        add.tap()
        let header = app.staticTexts.matching(NSPredicate(
            format: "label == %@ AND (identifier == %@ OR identifier == %@)",
            "添加模型", "local-genui-model-centered", "local-genui-model-bottom-sheet"
        )).firstMatch
        _ = try XCTUnwrap(header.waitForExistence(timeout: 8) ? header : nil, "Expected the blank model editor")
    }

    func testMiniAppDesktopActionOpensSystemShortcutEditor() {
        let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
        app.launchArguments = ["--harness-preview", "--drawer", "--simplified-chinese"]
        app.launchMobileReady()
        app.buttons["小应用"].firstMatch.tap()
        let card = app.buttons["miniapp:builtin-gomoku"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.press(forDuration: 0.8)
        app.buttons["添加桌面图标"].firstMatch.tap()

        let handoff = app.buttons["拷贝链接并打开快捷指令"]
        XCTAssertTrue(handoff.waitForExistence(timeout: 5))
        let guide = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        guide.name = "MiniAppDesktopGuide"
        guide.lifetime = .keepAlways
        add(guide)
        handoff.tap()

        let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
        let foreground = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in shortcuts.state == .runningForeground }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [foreground], timeout: 15), .completed)
        let actionSearchLabels = ["搜索操作", "Search Actions"]
        let actionSearch = shortcuts.descendants(matching: .any).matching(NSPredicate(
            format: "label IN %@ OR placeholderValue IN %@", actionSearchLabels, actionSearchLabels
        )).firstMatch
        XCTAssertTrue(actionSearch.waitForExistence(timeout: 15))
        let editor = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        editor.name = "MiniAppSystemShortcutEditor"
        editor.lifetime = .keepAlways
        add(editor)

        app.activate()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
    }

    func testOfflineMiniAppsOpenFromSidebar() {
        let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
        app.launchArguments = ["--harness-preview", "--drawer", "--simplified-chinese"]
        app.launchMobileReady()
        let miniapps = app.buttons["小应用"].firstMatch
        XCTAssertTrue(miniapps.waitForExistence(timeout: 15))
        let sidebar = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        sidebar.name = "OfflineMiniApp-Sidebar"
        sidebar.lifetime = .keepAlways
        add(sidebar)
        miniapps.tap()
        let carousel = app.buttons["miniapp:builtin-gomoku"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 10))
        XCTAssertTrue(carousel.isHittable)
        let gallery = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        gallery.name = "OfflineMiniApp-Gallery"
        gallery.lifetime = .keepAlways
        add(gallery)
        app.buttons["miniapp-view-toggle"].tap()
        for title in ["五子棋", "正则游乐场", "每日占卜"] {
            let entry = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 10))
            entry.tap()
            XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
            XCTAssertTrue(app.webViews.staticTexts[title].waitForExistence(timeout: 10), "The bundled page must render, not just create a WebView.")
            let evidence = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            evidence.name = "OfflineMiniApp-" + title
            evidence.lifetime = .keepAlways
            add(evidence)
            app.buttons["返回"].tap()
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
        }
        app.buttons["返回"].tap()
        XCTAssertTrue(miniapps.waitForExistence(timeout: 10))
        miniapps.tap()
        XCTAssertTrue(app.buttons["miniapp-view-toggle"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["miniapp-view-toggle"].label, "切换为卡片")
        app.buttons["miniapp-view-toggle"].tap()
        XCTAssertTrue(app.buttons["miniapp:builtin-daily-divination"].isHittable)
    }
}

private extension XCUIApplication {
    func launchMobileReady() {
        launch()
        let startup = descendants(matching: .any)["startup.brand"].firstMatch
        if startup.waitForExistence(timeout: 2) {
            let disappeared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: startup)
            XCTAssertEqual(XCTWaiter.wait(for: [disappeared], timeout: 15), .completed)
        }
        let later = buttons["稍后"]
        if later.waitForExistence(timeout: 3) { later.tap() }
    }
}

final class StreamingPresentationUITests: XCTestCase {
    func testMessageTimesAndQuietFailures() {
        let app = XCUIApplication()
        app.launchArguments = ["--streaming-regression", "--message-metadata-regression"]
        app.launch()
        let timestamps = app.staticTexts.matching(identifier: "chat.messageTimestamp")
        XCTAssertTrue(timestamps.firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(timestamps.count, 2)
        let summary = app.buttons["tool.summary.read"]
        let failure = app.buttons["tool.toggle.fetch"]
        XCTAssertTrue(summary.exists)
        XCTAssertFalse(failure.exists)
        tapDisclosure(summary, expanded: false)
        XCTAssertTrue(failure.wait(for: \.isHittable, toEqual: true, timeout: 10))
        tapToolRow(failure)
        XCTAssertTrue(app.staticTexts["HTTP 404"].waitForExistence(timeout: 10))
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Message times and expandable tool failure"
        capture.lifetime = .keepAlways
        add(capture)
    }

    func testCollapsedDraftKeepsTextAndShowsVoiceOnlyWhenExpanded() {
        let app = XCUIApplication()
        app.launchArguments = ["--composer-draft-preview"]
        app.launch()
        let input = app.textFields["composer.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        let original = input.value as? String
        XCTAssertTrue((original?.count ?? 0) > 300)
        let voice = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "语音输入", "Voice input"))
        XCTAssertEqual(voice.count, 0)
        let collapsed = XCTAttachment(screenshot: app.screenshot())
        collapsed.name = "Collapsed long draft"
        collapsed.lifetime = .keepAlways
        add(collapsed)
        input.tap()
        XCTAssertTrue(voice.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(input.value as? String, original)
    }

    func testComposerRoleRowsSelectSemanticModel() {
        let app = XCUIApplication()
        app.launchArguments = ["--composer-model-picker"]
        app.launch()
        let primary = app.buttons["composer.model.primary"]
        let fast = app.buttons["composer.model.fast"]
        XCTAssertTrue(primary.waitForExistence(timeout: 15))
        XCTAssertTrue(fast.exists)
        let menu = XCTAttachment(screenshot: app.screenshot())
        menu.name = "Model role picker"
        menu.lifetime = .keepAlways
        add(menu)
        fast.tap()
        let control = app.buttons["composer.modelControl"]
        XCTAssertTrue(control.waitForExistence(timeout: 3))
        XCTAssertTrue(["快速模型", "Fast model"].contains(control.value as? String ?? ""))
    }

    func testDirectoryOpenRoutesBeforeAuthorityIsReady() {
        let app = XCUIApplication()
        app.launchArguments = ["--streaming-regression", "--fixture-shell", "--open-loading-regression", "--status-regression"]
        app.launch()
        let open = app.buttons["fixture.openDelayed"]
        XCTAssertTrue(open.wait(for: \.isHittable, toEqual: true, timeout: 15))
        let initial = app.otherElements["conversation.session.fixture"]
        XCTAssertTrue(initial.waitForExistence(timeout: 10))
        open.tap()
        let detail = app.otherElements["conversation.session.delayed"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10), "Navigation must occur before the device binds")
        XCTAssertFalse(initial.exists)
        let loading = detail.otherElements["conversation.loading"]
        XCTAssertTrue(loading.waitForExistence(timeout: 5))
        app.buttons["fixture.bindTarget"].tap()
        XCTAssertTrue(detail.exists, "Binding the selected device must preserve pending navigation")
        XCTAssertTrue(loading.exists)
        app.buttons["fixture.finishLoading"].tap()
        XCTAssertTrue(detail.staticTexts["LOADED-SESSION"].waitForExistence(timeout: 5))
        XCTAssertFalse(loading.exists)
    }

    func testSubagentDetailsMatchHarmonyPreviewAndThinking() {
        let app = XCUIApplication()
        app.launchArguments = ["--streaming-regression", "--card-regression", "--subagent-detail-regression"]
        app.launch()
        let task = app.buttons["subagent.toggle.details"]
        XCTAssertTrue(task.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["LIVE-CHILD-THOUGHT"].exists)
        XCTAssertFalse(app.buttons["subagent.toggle.empty"].isEnabled, "Empty tasks must not offer disclosure")
        tapDisclosure(task, expanded: false)
        XCTAssertTrue(app.staticTexts["LIVE-CHILD-THOUGHT"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["OLD-CHILD-THOUGHT"].exists)
        XCTAssertFalse(app.staticTexts["PARENT-SUMMARY-MUST-NOT-REPEAT"].exists)
        let preview = app.staticTexts["subagent.output.child-output"]
        XCTAssertTrue(preview.exists)
        XCTAssertLessThanOrEqual(preview.label.count, 321)
        XCTAssertFalse(preview.label.contains("HIDDEN-OUTPUT-TAIL"))
        XCTAssertLessThan(preview.frame.height, 100)
        XCTAssertTrue(app.buttons["tool.toggle.child-one"].exists)
        XCTAssertTrue(app.buttons["tool.toggle.child-two"].exists)
        XCTAssertFalse(app.buttons["tool.summary.child-one"].exists)
        XCTAssertFalse(app.staticTexts["NESTED-OUTPUT"].exists)
        let nested = app.buttons["subagent.toggle.nested"]
        let nestedOutput = app.staticTexts["NESTED-OUTPUT"]
        tapDisclosure(nested, expanded: false)
        XCTAssertTrue(nestedOutput.waitForExistence(timeout: 10))
        tapDisclosure(nested, expanded: true)
        XCTAssertTrue(nestedOutput.waitForNonExistence(timeout: 10))
        app.buttons["fixture.send"].tap()
        XCTAssertTrue(task.label.contains("失败"), "Host failures must remain visible in the subtask header")
        XCTAssertTrue(preview.exists, "Completing keeps the manually opened subtask open")
        XCTAssertFalse(app.staticTexts["LIVE-CHILD-THOUGHT"].exists)
        tapDisclosure(app.buttons["thinking.toggle.child-old"], expanded: false)
        XCTAssertTrue(app.staticTexts["OLD-CHILD-THOUGHT"].waitForExistence(timeout: 10))
    }

    func testCardsMatchHarmonyExpansionAndOrdering() {
        let app = XCUIApplication()
        app.launchArguments = ["--streaming-regression", "--card-regression"]
        app.launch()
        let task = app.buttons["subagent.toggle.task"]
        XCTAssertTrue(task.waitForExistence(timeout: 15))
        let taskBody = app.staticTexts["TASK-BODY"]
        XCTAssertFalse(taskBody.exists, "Running tasks start collapsed")
        tapDisclosure(task, expanded: false)
        XCTAssertTrue(taskBody.waitForExistence(timeout: 10))
        app.buttons["fixture.send"].tap()
        XCTAssertTrue(taskBody.exists, "Status updates preserve the user's expansion")
        tapDisclosure(task, expanded: true)
        XCTAssertTrue(taskBody.waitForNonExistence(timeout: 10))
        let summary = app.buttons["tool.summary.one"]
        XCTAssertTrue(summary.exists)
        XCTAssertFalse(app.buttons["tool.toggle.one"].exists)
        XCTAssertFalse(app.staticTexts["REASON-BEFORE"].exists)
        XCTAssertFalse(app.buttons["thinking.toggle.before"].exists)
        XCTAssertTrue(app.buttons["tool.toggle.running"].exists)
        XCTAssertTrue(app.buttons["tool.toggle.failed"].exists)
        tapDisclosure(summary, expanded: false)
        let one = app.buttons["tool.toggle.one"]
        let two = app.buttons["tool.toggle.two"]
        XCTAssertTrue(one.waitForExistence(timeout: 10))
        let before = app.buttons["thinking.toggle.before"]
        let between = app.buttons["thinking.toggle.between"]
        XCTAssertTrue(before.exists && between.exists)
        XCTAssertLessThan(before.frame.minY, one.frame.minY)
        XCTAssertLessThan(one.frame.minY, between.frame.minY)
        XCTAssertLessThan(between.frame.minY, two.frame.minY)
        tapToolRow(one)
        XCTAssertTrue(app.staticTexts["OUTPUT-one"].waitForExistence(timeout: 10))
        tapToolRow(two)
        XCTAssertTrue(app.staticTexts["OUTPUT-two"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["OUTPUT-one"].exists, "Only one tool detail is expanded")
        XCTAssertLessThan(one.frame.minY, two.frame.minY)
        app.buttons["fixture.send"].tap()
        XCTAssertTrue(app.buttons["tool.toggle.three"].waitForExistence(timeout: 10),
            "Appending a completed tool must preserve the open summary")
        XCTAssertTrue(app.staticTexts["OUTPUT-two"].exists,
            "Appending tools must preserve the selected detail")
        tapDisclosure(summary, expanded: true)
        XCTAssertTrue(one.waitForNonExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["OUTPUT-two"].exists)
        XCTAssertTrue(app.staticTexts["ANSWER-AFTER-ACTIVITY"].isHittable)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.lifetime = .keepAlways
        add(capture)
    }

    private func tapDisclosure(_ button: XCUIElement, expanded: Bool) {
        let chevron = button.images[expanded ? "chevron.up" : "chevron.down"]
        XCTAssertTrue(chevron.waitForExistence(timeout: 10))
        chevron.tap()
    }

    private func tapToolRow(_ button: XCUIElement) {
        XCTAssertTrue(button.wait(for: \.isHittable, toEqual: true, timeout: 10))
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
    }

    func testSentUserBubbleStaysVisibleBeforeReply() {
        let app = XCUIApplication()
        app.launchArguments = ["--streaming-regression", "--user-bubble-regression"]
        app.launch()
        let start = app.buttons["fixture.send"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        let input = app.textFields.firstMatch
        input.tap()
        input.typeText("Message before reply")
        start.tap()
        let bubble = app.staticTexts["SENT-USER-BUBBLE"]
        XCTAssertTrue(bubble.waitForExistence(timeout: 5))
        for _ in 0..<4 {
            XCTAssertTrue(bubble.isHittable, "The sent message must remain visible while awaiting a reply")
            let tick = expectation(description: "Observe pending/acknowledged user bubble")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { tick.fulfill() }
            wait(for: [tick], timeout: 2)
        }
        XCTAssertTrue(app.staticTexts["Stream finished"].waitForExistence(timeout: 15))
        XCTAssertTrue(bubble.isHittable)
        XCTAssertTrue(app.staticTexts["SHORT-REPLY"].isHittable)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.lifetime = .keepAlways
        add(capture)
    }

    func testLongThinkingFoldsWhenAnswerStarts() {
        let app = XCUIApplication()
        app.launchArguments = ["--streaming-regression", "--thinking-regression"]
        app.launch()
        let start = app.buttons["fixture.send"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        let showAnswer = app.buttons["fixture.showThinkingAnswer"]
        XCTAssertTrue(showAnswer.wait(for: \.isEnabled, toEqual: true, timeout: 20))
        let thought = app.staticTexts["thinking.content.thought"]
        XCTAssertTrue(thought.waitForExistence(timeout: 10))
        XCTAssertTrue(thought.label.contains("Thinking segment 12"))
        XCTAssertGreaterThan(thought.frame.height, app.scrollViews.firstMatch.frame.height)
        showAnswer.tap()
        let answer = app.staticTexts["ANSWER-AFTER-THINKING"]
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        let folded = NSPredicate { _, _ in !thought.exists }
        expectation(for: folded, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(answer.wait(for: \.isHittable, toEqual: true, timeout: 5),
                      "The answer should scroll into view after the thinking block folds")
        app.buttons["fixture.finishThinkingAnswer"].tap()
        XCTAssertTrue(app.staticTexts["Stream finished"].waitForExistence(timeout: 10))
        XCTAssertTrue(answer.wait(for: \.isHittable, toEqual: true, timeout: 5))
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.lifetime = .keepAlways
        add(capture)
    }

    override func setUpWithError() throws { continueAfterFailure = false }

    func testHistoryPageKeepsPositionAndDoesNotQueueMoreDrags() {
        let app = XCUIApplication()
        app.launchArguments = ["--streaming-regression", "--history-pagination-regression"]
        app.launch()
        XCTAssertTrue(app.buttons["fixture.shortHistory"].waitForExistence(timeout: 15))
        app.buttons["fixture.shortHistory"].tap()
        let scroll = app.scrollViews.firstMatch
        // Multiple gestures while the page is in flight must not queue work.
        for _ in 0..<3 { scroll.swipeDown() }
        let requests = app.staticTexts["fixture.historyRequests"]
        XCTAssertEqual(requests.label, "History requests: 1")
        let row = app.staticTexts["History row 0"]
        XCTAssertTrue(row.exists)
        let top = row.frame.minY
        app.buttons["fixture.deliverHistory"].tap()
        let settled = NSPredicate { _, _ in app.buttons["timeline.loadOlder"].isEnabled }
        expectation(for: settled, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(row.frame.minY, top, accuracy: 4, "Prepending must preserve the existing visible row")
        XCTAssertEqual(requests.label, "History requests: 1", "Layout must not drain another page")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
    }

    func testPrependingHistoryPreservesVisibleRowOffset() {
        let app = XCUIApplication()
        app.launchArguments = ["--streaming-regression"]
        app.launch()
        let short = app.buttons["fixture.shortHistory"]
        XCTAssertTrue(short.waitForExistence(timeout: 15))
        short.tap()
        let load = app.buttons["timeline.loadOlder"]
        XCTAssertTrue(load.waitForExistence(timeout: 5))
        let row = app.staticTexts["History row 0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let originalY = row.frame.minY
        print("History anchor before: \(originalY)")
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "BeforePrepend"
        before.lifetime = .keepAlways
        add(before)
        load.tap()
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "AfterPrepend"
        after.lifetime = .keepAlways
        add(after)
        let restored = NSPredicate { _, _ in
            print("History anchor observed: exists=\(row.exists) y=\(row.frame.minY) expected=\(originalY)")
            return row.exists && abs(row.frame.minY - originalY) < 4
        }
        expectation(for: restored, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(load.exists)
    }

    func testUserCanReadHistoryAndResumeFollowingDuringStreaming() {
        let app = XCUIApplication()
        app.launchArguments = ["--streaming-regression"]
        app.launch()
        let start = app.buttons["fixture.send"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        scroll.swipeDown()
        scroll.swipeDown()
        let follow = app.buttons["timeline.scrollToBottom"]
        XCTAssertTrue(follow.waitForExistence(timeout: 5))
        follow.tap()
        XCTAssertTrue(app.staticTexts["Stream finished"].waitForExistence(timeout: 25))
        let end = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "STREAM-END")).firstMatch
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        XCTAssertTrue(end.isHittable)
        app.buttons["fixture.reset"].tap()
        XCTAssertTrue(start.exists)
        XCTAssertTrue(app.textFields.firstMatch.exists)
        expectation(for: NSPredicate { _, _ in !end.exists }, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
    }

    func testKeyboardDismissalAndLongStreamKeepContentVisible() {
        checkKeyboardAndStream(shell: false)
    }

    func testFullShellRemainsVisibleThroughKeyboardAndStreaming() {
        checkKeyboardAndStream(shell: true)
    }

    private func checkKeyboardAndStream(shell: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--streaming-regression"] + (shell ? ["--fixture-shell"] : [])
        app.launch()
        let start = app.buttons["fixture.send"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        let input = app.textFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("Draft before streaming")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        start.tap()
        let keyboardGone = NSPredicate { _, _ in !app.keyboards.firstMatch.exists }
        expectation(for: keyboardGone, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(start.exists)
        XCTAssertTrue(input.exists)
        XCTAssertTrue(app.staticTexts["Stream finished"].waitForExistence(timeout: 25))
        let end = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "STREAM-END")).firstMatch
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        XCTAssertTrue(end.isHittable, "The final response should remain in the viewport")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.lifetime = .keepAlways
        add(capture)
    }
}

/// Real-device diagnostics. Sending probes require an explicit environment opt-in.
final class RemoteTimelineScrollProbeUITests: XCTestCase {
    func testStreamInCurrentConversation() throws {
        guard ProcessInfo.processInfo.environment["PROBE_SEND_CURRENT"] == "1" else {
            throw XCTSkip("Explicit live send probe is not enabled")
        }
        let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
        app.activate()
        let conversation = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "conversation.session.")
        ).firstMatch
        XCTAssertTrue(conversation.waitForExistence(timeout: 10))
        let input = app.textFields["composer.input"]
        XCTAssertTrue(input.exists)
        input.tap()
        input.typeText("请写一篇约1500字的中文说明，分成十段，介绍聊天界面应有的交互体验。不要调用工具或修改文件。这是流式滚动诊断测试。")
        app.buttons["arrow.up"].tap()
        for index in 0..<6 {
            let pause = expectation(description: "Allow streaming progress")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { pause.fulfill() }
            wait(for: [pause], timeout: 3)
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "StreamPhase\(index)"
            capture.lifetime = .keepAlways
            add(capture)
            if index == 2 || index == 4 {
                let scroll = conversation.scrollViews.firstMatch
                scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
                    .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
            }
        }
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "AfterStreamingDrag"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    func testInspectCurrentScreen() {
        let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
        app.activate()
        if app.buttons["查看设备"].waitForExistence(timeout: 3) { app.buttons["查看设备"].tap() }
        let device = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sidebar.device.")).firstMatch
        if !device.waitForExistence(timeout: 8), app.buttons["查看设备"].exists {
            app.buttons["查看设备"].tap()
            _ = device.waitForExistence(timeout: 8)
        }
        if device.exists && !device.isHittable && app.buttons["打开侧栏"].exists {
            app.buttons["打开侧栏"].tap()
        }
        if device.exists && device.isHittable {
            device.tap()
            let workspace = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sidebar.workspace.")).firstMatch
            _ = workspace.waitForExistence(timeout: 20)
        }
        if let sessionID = ProcessInfo.processInfo.environment["PROBE_SESSION_ID"] {
            let session = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "sidebar.session.", sessionID)).firstMatch
            let workspaces = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sidebar.workspace."))
            for workspace in workspaces.allElementsBoundByIndex {
                if session.exists { break }
                if workspace.isHittable { workspace.tap(); _ = session.waitForExistence(timeout: 5) }
            }
            if session.exists && session.isHittable {
                session.tap()
                let input = app.textFields["composer.input"]
                if input.waitForExistence(timeout: 15) {
                    let message = ProcessInfo.processInfo.environment["PROBE_MESSAGE"] ?? "请仅用三段简短中文介绍你能做什么。不要调用工具或修改任何文件。这是一条手机流式显示测试消息。"
                    input.tap()
                    if (input.value as? String) != message { input.typeText(message) }
                    let send = app.buttons["arrow.up"]
                    if send.exists && send.isEnabled {
                        send.tap()
                        let sent = XCTAttachment(screenshot: app.screenshot())
                        sent.name = "ImmediatelyAfterSend"
                        sent.lifetime = .keepAlways
                        add(sent)
                        let draftCleared = NSPredicate { _, _ in (input.value as? String) != message }
                        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: draftCleared, object: nil)], timeout: 10)
                        let settled = NSPredicate { _, _ in !app.buttons["停止"].exists }
                        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: nil)], timeout: 45)
                        let conversation = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "conversation.session.")).firstMatch
                        let scroll = conversation.scrollViews.firstMatch
                        if scroll.exists {
                            let beforeDrag = XCTAttachment(string: app.debugDescription)
                            beforeDrag.name = "AfterReplyBeforeDrag"
                            beforeDrag.lifetime = .keepAlways
                            add(beforeDrag)
                            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
                        }
                    }
                }
            }
        }
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "CurrentScreen"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    func testProfileCurrentComposerInteractions() {
        let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
        app.activate()
        let header = app.buttons["打开侧栏"]
        if header.exists && header.frame.minX > 100 { header.tap() }
        let input = app.textFields["composer.input"]
        if !input.waitForExistence(timeout: 10) {
            if app.buttons["查看设备"].exists { app.buttons["查看设备"].tap() }
            let device = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sidebar.device.")).firstMatch
            if !device.isHittable && header.exists { header.tap() }
            XCTAssertTrue(device.waitForExistence(timeout: 10))
            device.tap()
            let workspaces = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sidebar.workspace."))
            XCTAssertTrue(workspaces.firstMatch.waitForExistence(timeout: 20))
            guard let sessionID = ProcessInfo.processInfo.environment["PROBE_SESSION_ID"] else {
                XCTFail("A session ID is required to open a closed conversation"); return
            }
            let session = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "sidebar.session.", sessionID)).firstMatch
            for workspace in workspaces.allElementsBoundByIndex {
                if session.exists { break }
                if workspace.isHittable { workspace.tap(); _ = session.waitForExistence(timeout: 5) }
            }
            XCTAssertTrue(session.waitForExistence(timeout: 10))
            session.tap()
        }
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        for cycle in 0..<6 {
            let pause = expectation(description: "Prepare interaction profiling")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { pause.fulfill() }
            wait(for: [pause], timeout: 6)
            print("ComposerProbe cycle=\(cycle) action=focus begin")
            input.tap()
            let picker = app.buttons["选择模型"]
            XCTAssertTrue(picker.waitForExistence(timeout: 10))
            print("ComposerProbe cycle=\(cycle) action=model-picker begin")
            picker.tap()
            let close = app.buttons["关闭"].firstMatch
            XCTAssertTrue(close.waitForExistence(timeout: 10))
            close.tap()
            let conversation = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "conversation.session.")).firstMatch
            conversation.scrollViews.firstMatch.swipeDown()
            print("ComposerProbe cycle=\(cycle) action=finished")
        }
    }

    func testCurrentConversationCanScroll() throws {
        let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
        app.activate()
        let before = XCTAttachment(string: app.debugDescription)
        before.name = "RemoteTimelineBeforeDrag"
        before.lifetime = .keepAlways
        add(before)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "RemoteTimelineBeforeDrag"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let conversation = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "conversation.session.")
        ).firstMatch
        let scroll = conversation.scrollViews.firstMatch
        guard scroll.waitForExistence(timeout: 10) else {
            XCTFail("No conversation scroll view is available")
            return
        }
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        for _ in 0..<12 { start.press(forDuration: 0.1, thenDragTo: end) }
        let after = XCTAttachment(string: app.debugDescription)
        after.name = "RemoteTimelineAfterDrag"
        after.lifetime = .keepAlways
        add(after)
        let afterScreenshot = XCTAttachment(screenshot: app.screenshot())
        afterScreenshot.name = "RemoteTimelineAfterDrag"
        afterScreenshot.lifetime = .keepAlways
        add(afterScreenshot)
    }
}

/// Opt-in live Relay probe. The caller supplies the exact authorized desktop;
/// ordinary test runs skip it and never choose a user's device implicitly.
final class RemoteTerminalLiveUITests: XCTestCase {
    func testNativeTerminalInputAndClose() throws {
        let target = ProcessInfo.processInfo.environment["OPENBITFUN_LIVE_TERMINAL_DEVICE"] ?? ""
        try XCTSkipIf(target.isEmpty, "Set OPENBITFUN_LIVE_TERMINAL_DEVICE to an authorized test desktop.")
        let sshName = ProcessInfo.processInfo.environment["OPENBITFUN_LIVE_TERMINAL_SSH"] ?? ""
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
        app.launch()
        defer {
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "LiveTerminalFinal"; capture.lifetime = .keepAlways; add(capture)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "LiveTerminalHierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        let sidebar = app.buttons["打开侧栏"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 30))
        let sidebarReady = NSPredicate { object, _ in (object as? XCUIElement)?.isHittable == true }
        expectation(for: sidebarReady, evaluatedWith: sidebar); waitForExpectations(timeout: 30)
        sidebar.tap()
        let device = app.buttons["sidebar.device.\(target)"]
        XCTAssertTrue(device.waitForExistence(timeout: 30))
        let hittable = NSPredicate { object, _ in (object as? XCUIElement)?.isHittable == true }
        expectation(for: hittable, evaluatedWith: device); waitForExpectations(timeout: 15)
        device.tap()
        let tools = app.buttons["sidebar.deviceTools"]
        let enabled = NSPredicate { object, _ in (object as? XCUIElement)?.isEnabled == true }
        expectation(for: enabled, evaluatedWith: tools); waitForExpectations(timeout: 30)
        tools.tap()
        if !sshName.isEmpty {
            let location = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "受控设备本机")).firstMatch
            XCTAssertTrue(location.waitForExistence(timeout: 20)); location.tap()
            let saved = app.buttons[sshName]
            XCTAssertTrue(saved.waitForExistence(timeout: 10)); saved.tap()
            let entry = app.staticTexts["boot"]
            XCTAssertTrue(entry.waitForExistence(timeout: 30), "Saved SSH root listing must hydrate.")
            let listing = XCTAttachment(screenshot: app.screenshot()); listing.name = "LiveSshFiles"; listing.lifetime = .keepAlways; add(listing)
        }
        let terminalTab = app.buttons["device.tools.panel.terminal"]
        XCTAssertTrue(terminalTab.waitForExistence(timeout: 20)); terminalTab.tap()
        let openTerminal = app.buttons["device.tools.openTerminal"]
        XCTAssertTrue(openTerminal.waitForExistence(timeout: 20))
        if ProcessInfo.processInfo.environment["OPENBITFUN_LIVE_TOOLS_TABS_ONLY"] == "1" {
            XCTAssertTrue(terminalTab.isSelected)
            let filesTab = app.buttons["device.tools.panel.files"]
            filesTab.tap()
            XCTAssertTrue(filesTab.isSelected)
            XCTAssertFalse(openTerminal.exists)
            terminalTab.tap()
            XCTAssertTrue(openTerminal.waitForExistence(timeout: 10))
            XCTAssertTrue(terminalTab.isSelected)
            XCTAssertFalse(app.textViews["Terminal input"].exists)
            if ProcessInfo.processInfo.environment["OPENBITFUN_LIVE_TOOLS_ROTATE"] == "1" {
                defer { XCUIDevice.shared.orientation = .portrait }
                XCUIDevice.shared.orientation = .landscapeLeft
                XCTAssertTrue(openTerminal.waitForExistence(timeout: 15))
                XCTAssertTrue(terminalTab.isSelected)
                let wide = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                wide.name = "DeviceToolsWide"; wide.lifetime = .keepAlways; add(wide)
                filesTab.tap()
                XCTAssertTrue(filesTab.isSelected)
                terminalTab.tap()
                XCTAssertTrue(openTerminal.waitForExistence(timeout: 10))
            }
            return
        }
        openTerminal.tap()
        let terminal = app.webViews.firstMatch
        XCTAssertTrue(terminal.waitForExistence(timeout: 20))
        let input = app.textViews["Terminal input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.2)).tap()
        input.typeText(sshName.isEmpty ? "echo IOS_TERMINAL_PARITY\n" : "uname -s\n")
        // The screenshot records the actual remote response; layout and input
        // checks alone do not prove that the host executed the command.
        let output = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", sshName.isEmpty ? "IOS_TERMINAL_PARITY" : "Linux")).firstMatch
        _ = output.waitForExistence(timeout: 8)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "LiveTerminalOutput"; capture.lifetime = .keepAlways; add(capture)
        XCTAssertTrue(app.buttons["停止"].exists)
        app.buttons["关闭终端"].tap()
        XCTAssertTrue(app.buttons["device.tools.openTerminal"].waitForExistence(timeout: 20))
        let back = app.buttons["返回"].firstMatch
        expectation(for: hittable, evaluatedWith: back); waitForExpectations(timeout: 10)
        let closed = XCTAttachment(screenshot: app.screenshot())
        closed.name = "ClosedTerminalNavigation"; closed.lifetime = .keepAlways; add(closed)
        app.buttons["device.tools.openTerminal"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 20))
        terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.2)).tap()
        input.typeText("pwd\n")
        let reopened = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", sshName.isEmpty ? "/Users/" : "/home/")).firstMatch
        _ = reopened.waitForExistence(timeout: 8)
        let second = XCTAttachment(screenshot: app.screenshot())
        second.name = "ReopenedTerminalOutput"; second.lifetime = .keepAlways; add(second)
        app.buttons["关闭终端"].tap()
        XCTAssertTrue(app.buttons["device.tools.openTerminal"].waitForExistence(timeout: 20))
    }
}

/// Opt-in real filesystem write. The caller must provide an authorized device
/// and a fresh temporary destination; the host rejects overwriting an old file.
final class RemoteHomeLiveUITests: XCTestCase {
    func testSelectedDeviceHomeAndSidebar() throws {
        let target = ProcessInfo.processInfo.environment["OPENBITFUN_LIVE_FILE_DEVICE"] ?? ""
        try XCTSkipIf(target.isEmpty, "Supply an authorized device.")
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
        app.launchMobileReady()
        let sidebar = app.buttons["打开侧栏"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 30)); sidebar.tap()
        let device = app.buttons["sidebar.device.\(target)"]
        XCTAssertTrue(device.waitForExistence(timeout: 30)); device.tap()
        let tools = app.buttons["sidebar.deviceTools"]
        expectation(for: NSPredicate { object, _ in (object as? XCUIElement)?.isEnabled == true }, evaluatedWith: tools)
        waitForExpectations(timeout: 30)
        let drawer = XCTAttachment(screenshot: app.screenshot()); drawer.name = "LiveSelectedDeviceSidebar"; drawer.lifetime = .keepAlways; add(drawer)
        if ProcessInfo.processInfo.environment["OPENBITFUN_LIVE_HEALTH_OUTAGE"] == "1" {
            let connectedValue = device.value as? String
            XCTAssertNotNil(connectedValue)
            print("LIVE_HEALTH_READY_FOR_HOST_PAUSE")
            expectation(for: NSPredicate { object, _ in
                (object as? XCUIElement)?.value as? String != connectedValue
            }, evaluatedWith: device)
            waitForExpectations(timeout: 90)
            XCTAssertTrue(device.exists, "A lost host must not remove the selected device.")
            let outage = XCTAttachment(screenshot: app.screenshot())
            outage.name = "LiveHostUnavailableSidebar"; outage.lifetime = .keepAlways; add(outage)
            expectation(for: NSPredicate { object, _ in
                (object as? XCUIElement)?.value as? String == connectedValue
            }, evaluatedWith: device)
            waitForExpectations(timeout: 90)
            XCTAssertTrue(device.exists)
            let recovered = XCTAttachment(screenshot: app.screenshot())
            recovered.name = "LiveHostRecoveredSidebar"; recovered.lifetime = .keepAlways; add(recovered)
        }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.45)).tap()
        let recent = app.staticTexts["最近会话"]
        XCTAssertTrue(recent.waitForExistence(timeout: 30))
        let home = XCTAttachment(screenshot: app.screenshot()); home.name = "LiveSelectedDeviceHome"; home.lifetime = .keepAlways; add(home)
    }
}

final class RemoteFileBrowserLiveUITests: XCTestCase {
    func testCreateFileFromDeviceToolsWithKeyboardOpen() throws {
        XCUIDevice.shared.orientation = .portrait
        let environment = ProcessInfo.processInfo.environment
        let target = environment["OPENBITFUN_LIVE_FILE_DEVICE"] ?? ""
        let path = environment["OPENBITFUN_LIVE_FILE_PATH"] ?? ""
        try XCTSkipIf(target.isEmpty || path.isEmpty, "Supply an authorized device and fresh temporary file path.")
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
        app.launch()
        defer {
            let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "LiveFilesFinal"; capture.lifetime = .keepAlways; add(capture)
            let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "LiveFilesHierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        let sidebar = app.buttons["打开侧栏"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 30))
        let hittable = NSPredicate { object, _ in (object as? XCUIElement)?.isHittable == true }
        expectation(for: hittable, evaluatedWith: sidebar); waitForExpectations(timeout: 30); sidebar.tap()
        let device = app.buttons["sidebar.device.\(target)"]
        XCTAssertTrue(device.waitForExistence(timeout: 30)); expectation(for: hittable, evaluatedWith: device); waitForExpectations(timeout: 15); device.tap()
        let tools = app.buttons["sidebar.deviceTools"]
        expectation(for: NSPredicate { object, _ in (object as? XCUIElement)?.isEnabled == true }, evaluatedWith: tools); waitForExpectations(timeout: 30); tools.tap()
        let sshName = environment["OPENBITFUN_LIVE_FILE_SSH"] ?? ""
        if !sshName.isEmpty {
            let location = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "受控设备本机")).firstMatch
            XCTAssertTrue(location.waitForExistence(timeout: 20)); location.tap()
            let saved = app.buttons[sshName]
            XCTAssertTrue(saved.waitForExistence(timeout: 10)); saved.tap()
            XCTAssertTrue(app.staticTexts["boot"].waitForExistence(timeout: 30))
        }
        let create = app.buttons["file.browser.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 30)); expectation(for: NSPredicate { object, _ in (object as? XCUIElement)?.isEnabled == true }, evaluatedWith: create); waitForExpectations(timeout: 30)
        let listing = XCTAttachment(screenshot: app.screenshot()); listing.name = "LiveFileListing"; listing.lifetime = .keepAlways; add(listing)
        let editRelativePath = environment["OPENBITFUN_LIVE_FILE_EDIT_RELATIVE_PATH"] ?? ""
        if !editRelativePath.isEmpty {
            defer { XCUIDevice.shared.orientation = .portrait }
            app.buttons["文件排序"].tap()
            app.buttons["修改时间：最新优先"].tap()
            for component in editRelativePath.split(separator: "/").map(String.init) {
                let entry = app.buttons[component].firstMatch
                _ = entry.waitForExistence(timeout: 10)
                for _ in 0..<12 {
                    if entry.exists && entry.isHittable { break }
                    app.swipeUp()
                }
                XCTAssertTrue(entry.isHittable, "Expected owned test entry \(component)")
                entry.tap()
            }
            let editor = app.textViews.matching(NSPredicate(format: "enabled == true")).firstMatch
            XCTAssertTrue(editor.waitForExistence(timeout: 20)); editor.tap()
            editor.typeText(" ios-lifecycle-draft")
            let draft = editor.value as? String
            XCTAssertTrue(draft?.contains("ios-lifecycle-draft") == true)
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertEqual(editor.value as? String, draft)
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertTrue(editor.waitForExistence(timeout: 10))
            XCTAssertEqual(editor.value as? String, draft)
            XCUIDevice.shared.orientation = .portrait
            XCTAssertEqual(editor.value as? String, draft)
            let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "LiveDraftAfterLifecycle"; capture.lifetime = .keepAlways; add(capture)
            app.buttons["返回"].firstMatch.tap()
            let cancel = app.buttons["取消"].firstMatch
            if cancel.exists { cancel.tap() }
            else {
                // Native popover confirmation omits Cancel; outside tap dismisses it.
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
            }
            XCTAssertEqual(editor.value as? String, draft)
            app.buttons["返回"].firstMatch.tap()
            app.buttons["放弃"].firstMatch.tap()
            XCTAssertTrue(create.waitForExistence(timeout: 10))
            return
        }
        if environment["OPENBITFUN_LIVE_FILE_DOWNLOAD"] == "1" {
            let components = path.split(separator: "/").map(String.init)
            for component in components.dropLast() {
                let folder = app.buttons[component].firstMatch
                for _ in 0..<12 {
                    if folder.exists && folder.isHittable { break }
                    app.swipeUp()
                }
                XCTAssertTrue(folder.isHittable, "Expected remote directory \(component)")
                folder.tap()
                XCTAssertTrue(create.waitForExistence(timeout: 20))
                expectation(for: NSPredicate { object, _ in (object as? XCUIElement)?.isEnabled == true }, evaluatedWith: create)
                waitForExpectations(timeout: 30)
            }
            let actions = app.buttons["file.browser.actions.\(path)"]
            XCTAssertTrue(actions.waitForExistence(timeout: 20)); actions.tap()
            app.buttons["下载"].tap()
            let save = app.buttons.matching(NSPredicate(format: "label IN %@", ["存储", "保存", "Save"])).firstMatch
            XCTAssertTrue(save.waitForExistence(timeout: 30))
            let export = XCTAttachment(screenshot: app.screenshot()); export.name = "LiveDownloadExporter"; export.lifetime = .keepAlways; add(export)
            save.tap()
            expectation(for: NSPredicate { object, _ in (object as? XCUIElement)?.exists == false }, evaluatedWith: save)
            waitForExpectations(timeout: 30)
            return
        }
        let verifyUploadCancel = environment["OPENBITFUN_LIVE_FILE_UPLOAD_CANCEL"] == "1"
        let uploadSource = environment["OPENBITFUN_LIVE_FILE_UPLOAD_SOURCE"] ?? ""
        create.tap(); app.buttons[(verifyUploadCancel || !uploadSource.isEmpty) ? "上传文件" : "新建文件"].tap()
        let input = app.textFields["file.action.name"]
        XCTAssertTrue(input.waitForExistence(timeout: 10)); input.tap(); input.typeText(path)
        let submit = app.buttons["file.action.submit"]
        XCTAssertTrue(submit.isHittable)
        let form = XCTAttachment(screenshot: app.screenshot()); form.name = "LiveFileFormKeyboard"; form.lifetime = .keepAlways; add(form)
        submit.tap()
        if !uploadSource.isEmpty {
            let browse = app.buttons["浏览"].firstMatch
            XCTAssertTrue(browse.waitForExistence(timeout: 15)); browse.tap()
            let onPhone = app.staticTexts.matching(NSPredicate(format: "label IN %@", ["我的 iPhone", "我的iPhone", "On My iPhone"])).firstMatch
            if onPhone.waitForExistence(timeout: 5) { onPhone.tap() }
            let picker = XCTAttachment(string: app.debugDescription); picker.name = "LiveUploadBrowseHierarchy"; picker.lifetime = .keepAlways; add(picker)
            let file = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", uploadSource)).firstMatch
            XCTAssertTrue(file.waitForExistence(timeout: 15)); file.tap()
        }
        if verifyUploadCancel {
            let cancel = app.buttons["Cancel"].firstMatch
            let localizedCancel = app.buttons["取消"].firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 10) || localizedCancel.waitForExistence(timeout: 10))
            let picker = XCTAttachment(screenshot: app.screenshot()); picker.name = "LiveUploadPicker"; picker.lifetime = .keepAlways; add(picker)
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "LiveUploadPickerHierarchy"; tree.lifetime = .keepAlways; add(tree)
            (cancel.exists ? cancel : localizedCancel).tap()
            XCTAssertTrue(input.waitForExistence(timeout: 10))
            XCTAssertEqual(input.value as? String, path, "Cancelling selection must preserve the upload destination.")
            XCTAssertTrue(submit.isEnabled)
            app.buttons["取消"].firstMatch.tap()
        }
        expectation(for: NSPredicate { object, _ in (object as? XCUIElement)?.exists == false }, evaluatedWith: input); waitForExpectations(timeout: 30)
    }
}

/// Opt-in live host check using an explicitly named disposable test conversation.
final class RemoteMailboxLiveUITests: XCTestCase {
    func testQuestionRoundTrip() throws {
        let env = ProcessInfo.processInfo.environment
        let permissionReply = env["OPENBITFUN_LIVE_MAILBOX_PERMISSION_REPLY"]
        let title = env["OPENBITFUN_LIVE_MAILBOX_TITLE"] ?? ""
        let deviceID = env["OPENBITFUN_LIVE_FILE_DEVICE"] ?? ""
        let workspacePath = env["OPENBITFUN_LIVE_MAILBOX_WORKSPACE"] ?? ""
        try XCTSkipIf(title.isEmpty || deviceID.isEmpty || workspacePath.isEmpty, "Supply the authorized test conversation title.")
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.openbitfun.mobile.ios")
        app.launch()
        defer {
            let image = XCTAttachment(screenshot: app.screenshot()); image.name = "MailboxFinal"; image.lifetime = .keepAlways; add(image)
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "MailboxHierarchy"; tree.lifetime = .keepAlways; add(tree)
        }
        let sidebar = app.buttons["打开侧栏"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 30))
        let hittable = NSPredicate { object, _ in (object as? XCUIElement)?.isHittable == true }
        expectation(for: hittable, evaluatedWith: sidebar); waitForExpectations(timeout: 30)
        sidebar.tap()
        let device = app.buttons["sidebar.device.\(deviceID)"]
        XCTAssertTrue(device.waitForExistence(timeout: 30))
        if !device.isHittable { sidebar.tap() }
        expectation(for: hittable, evaluatedWith: device); waitForExpectations(timeout: 30); device.tap()
        let workspacePrefix = env["OPENBITFUN_LIVE_MAILBOX_DISCLOSURE"] == "1" ? "sidebar.workspaceDisclosure" : "sidebar.workspace"
        let workspace = app.buttons["\(workspacePrefix).\(deviceID).\(workspacePath)"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 30)); workspace.tap()
        let session = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "sidebar.session.", title)).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 30)); session.tap()
        if env["OPENBITFUN_LIVE_MAILBOX_READ_ONLY"] == "1" {
            let message = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "message.user.")).firstMatch
            XCTAssertTrue(message.waitForExistence(timeout: 60), "Existing conversation must hydrate without sending another message.")
            if let marker = env["OPENBITFUN_LIVE_INCOMING_MARKER"], !marker.isEmpty {
                let incoming = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", marker)).firstMatch
                XCTAssertTrue(incoming.waitForExistence(timeout: 120), "Another controller's message must arrive without reopening the conversation.")
                if let reply = env["OPENBITFUN_LIVE_INCOMING_REPLY"], !reply.isEmpty {
                    XCTAssertTrue(app.staticTexts[reply].waitForExistence(timeout: 120), "The other controller's completed reply must arrive on the same subscription.")
                }
            }
            if let expectedModel = env["OPENBITFUN_LIVE_EXPECTED_MODEL"], !expectedModel.isEmpty {
                let input = app.textFields["composer.input"]
                XCTAssertTrue(input.waitForExistence(timeout: 15)); input.tap()
                let modelLabel = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", expectedModel)).firstMatch
                XCTAssertTrue(modelLabel.waitForExistence(timeout: 30), "The opened session must hydrate its model without a manual refresh.")
                let image = XCTAttachment(screenshot: app.screenshot())
                image.name = "InitialSessionModel"; image.lifetime = .keepAlways; add(image)
                if let changedModel = env["OPENBITFUN_LIVE_CHANGED_MODEL"], !changedModel.isEmpty {
                    print("LIVE_MODEL_READY_FOR_EXTERNAL_CHANGE")
                    let changed = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", changedModel)).firstMatch
                    XCTAssertTrue(changed.waitForExistence(timeout: 90), "Another controller's model change must arrive without reopening or refreshing.")
                    let changedImage = XCTAttachment(screenshot: app.screenshot())
                    changedImage.name = "ExternalSessionModel"; changedImage.lifetime = .keepAlways; add(changedImage)
                }
            }
            if env["OPENBITFUN_LIVE_SIDEBAR_CAPTURE"] == "1" {
                XCTAssertTrue(sidebar.waitForExistence(timeout: 10)); sidebar.tap()
                XCTAssertTrue(app.buttons["刷新设备"].waitForExistence(timeout: 10))
                XCTAssertTrue(session.waitForExistence(timeout: 10))
                let image = XCTAttachment(screenshot: app.screenshot())
                image.name = "SelectedSessionSidebar"; image.lifetime = .keepAlways; add(image)
            }
            return
        }
        if env["OPENBITFUN_LIVE_MAILBOX_RESUME"] != "1" {
            let input = app.textFields["composer.input"]
            XCTAssertTrue(input.waitForExistence(timeout: 30)); input.tap()
            input.typeText(permissionReply == nil ?
                "UI test: Please use AskUserQuestion again to ask me to choose Alpha or Beta. Wait for my answer. Do not modify files." :
                "Approval test. Use ExecCommand to run ls -ld /tmp. If rejected stop. Do not retry or modify files.")
            app.buttons["发送"].tap()
        }
        if let permissionReply {
            XCTAssertTrue(["reject", "approve"].contains(permissionReply))
            let buttons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "permission.\(permissionReply)."))
            let reply = buttons.firstMatch
            XCTAssertTrue(reply.waitForExistence(timeout: 180))
            XCTAssertEqual(buttons.count, 1, "Only the mailbox owns the pending permission action.")
            XCTAssertTrue(reply.isEnabled)
            let image = XCTAttachment(screenshot: app.screenshot()); image.name = "MailboxPermission"; image.lifetime = .keepAlways; add(image)
            reply.tap()
            expectation(for: NSPredicate { object, _ in (object as? XCUIElement)?.exists == false }, evaluatedWith: reply)
            waitForExpectations(timeout: 60)
            XCTAssertEqual(buttons.count, 0)
            return
        }
        let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "question.option.", ".Beta"))
        let choice = choices.firstMatch
        let questionTimeout = min(300, max(60, Double(env["OPENBITFUN_LIVE_MAILBOX_WAIT_SECONDS"] ?? "60") ?? 60))
        XCTAssertTrue(choice.waitForExistence(timeout: questionTimeout))
        XCTAssertEqual(choices.count, 1, "The mailbox and transcript must not expose duplicate answer forms.")
        choice.tap()
        let submit = app.buttons["发送回复"].firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: 10)); XCTAssertTrue(submit.isEnabled)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "MailboxQuestion"; image.lifetime = .keepAlways; add(image)
        submit.tap()
        expectation(for: NSPredicate { object, _ in (object as? XCUIElement)?.exists == false }, evaluatedWith: submit)
        waitForExpectations(timeout: 30)
        XCTAssertEqual(choices.count, 0, "An answered mailbox must not reopen its stale transcript form.")
    }
}
