/**
 * @file    LoginItem.swift
 * @author  James Zeman
 * @date    28 OCT 2026
 * @brief   Opening BobcatBar at login. macOS keeps the setting (System Settings >
 *          General > Login Items), so it's read fresh rather than stored in config.json.
 */
import Foundation
import ServiceManagement

enum LoginItem {
    /**
     * @brief   Whether BobcatBar opens at login.
     */
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /**
     * @brief   Turns opening at login on or off.
     *
     * @param   on  the new setting.
     * @return  an error message, or nil when it worked.
     */
    @discardableResult
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return "Couldn't change Login Items: \(error.localizedDescription)"
        }
    }

    /**
     * @brief   Why opening at login wouldn't stick, or nil if it would. An app opened
     *          straight from Downloads runs from a temporary copy (App Translocation),
     *          and a login item or update would point at that copy.
     */
    static var placementProblem: String? {
        let path = Bundle.main.bundlePath
        if path.contains("/AppTranslocation/") || path.hasPrefix("/Volumes/") {
            return "Move BobcatBar to your Applications folder and open it from there first."
        }
        if path.contains("/Downloads/") {
            return "BobcatBar is in Downloads. Move it to Applications so it keeps working."
        }
        return nil
    }
}
