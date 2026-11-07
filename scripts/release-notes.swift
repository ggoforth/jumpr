#!/usr/bin/env swift
// One entry in site/releases.json feeds the changelog page, the update window and the GitHub
// release, so the three cannot disagree.
//
//   swift scripts/release-notes.swift check            validates the file
//   swift scripts/release-notes.swift html <version>   the entry as HTML, for the appcast
//   swift scripts/release-notes.swift body <version>   the entry for the GitHub release
//
// Entries hold a little inline HTML. The page and the update window show it as written, and
// GitHub renders it inside Markdown, so nothing here has to convert it.
import Foundation

struct Release: Decodable {
    let version: String
    let date: String
    let summary: String
    let bullets: [String]?
    let note: String?

    var texts: [String] { [summary] + (bullets ?? []) + (note.map { [$0] } ?? []) }
}
struct Feed: Decodable { let releases: [Release] }

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("release-notes: \(message)\n".utf8))
    exit(1)
}

func has(_ text: String, _ pattern: String) -> Bool {
    text.range(of: pattern, options: .regularExpression) != nil
}

func problems(in releases: [Release]) -> [String] {
    var found: [String] = []
    if releases.isEmpty { found.append("there are no releases") }
    var newer: [Int]?
    for release in releases {
        let name = release.version
        if !has(name, #"^v[0-9]+\.[0-9]+(\.[0-9]+)?$"#) { found.append("\(name): version must look like v1.0.0") }
        if !has(release.date, #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#) { found.append("\(name): date must look like 2026-11-06") }
        if release.summary.isEmpty { found.append("\(name): summary is empty") }
        // The page injects these as HTML, and the appcast wraps them in CDATA.
        for text in release.texts where has(text, #"<(?!/?(strong|em|code)>|a href="https://[^"]*">|/a>)"#) || text.contains("]]>") {
            found.append("\(name): only <strong>, <em>, <code> and https links are allowed: \(text)")
        }
        let parts = name.dropFirst().split(separator: ".").compactMap { Int($0) }
        if let newer, !parts.lexicographicallyPrecedes(newer) { found.append("\(name): releases must run newest first") }
        newer = parts
    }
    return found
}

func html(_ release: Release) -> String {
    var lines = ["<p>\(release.summary)</p>"]
    if let bullets = release.bullets { lines.append("<ul>" + bullets.map { "<li>\($0)</li>" }.joined() + "</ul>") }
    if let note = release.note { lines.append("<p>\(note)</p>") }
    return lines.joined(separator: "\n")
}

func body(_ release: Release) -> String {
    var blocks = [release.summary]
    if let bullets = release.bullets { blocks.append(bullets.map { "- \($0)" }.joined(separator: "\n")) }
    if let note = release.note { blocks.append(note) }
    blocks.append("If you have an earlier version, Jumpr offers this update on its own, or choose **Check for Updates…** from the menu bar icon.")
    blocks.append("**Install:** download `Jumpr.zip`, unzip, move Jumpr to Applications and open it. It asks for the Accessibility permission on first launch.")
    blocks.append("More at [getjumpr.app](https://getjumpr.app), and every release at [getjumpr.app/changelog.html](https://getjumpr.app/changelog.html).")
    return blocks.joined(separator: "\n\n")
}

let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../site/releases.json")
guard let data = try? Data(contentsOf: file) else { die("cannot read \(file.path)") }
let releases: [Release]
do { releases = try JSONDecoder().decode(Feed.self, from: data).releases } catch { die("site/releases.json: \(error)") }

let found = problems(in: releases)
if !found.isEmpty { die(found.joined(separator: "\n")) }

let arguments = Array(CommandLine.arguments.dropFirst())
switch (arguments.first, arguments.count) {
case ("check", 1):
    print("site/releases.json: \(releases.count) releases, newest \(releases[0].version)")
case ("html", 2), ("body", 2):
    let version = "v" + arguments[1]
    guard let release = releases.first(where: { $0.version == version }) else {
        die("site/releases.json has no entry for \(version). Write it first: see the release-notes skill.")
    }
    print(arguments[0] == "html" ? html(release) : body(release))
default:
    die("usage: release-notes.swift check | html <version> | body <version>")
}
