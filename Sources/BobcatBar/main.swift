/**
 * @file    main.swift
 * @author  James Zeman
 * @date    9 SEP 2026
 * @brief   BobcatBar entry point: starts the menu-bar app.
 */
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
