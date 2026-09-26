# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- Pipes v2 in-app messaging for HTML, images, surveys, sticky banners, inline placements, and stories on Android and iOS.
- Shared frequency admission, profile targeting, installation caps, and interaction reporting.

### Fixed

- Avoid duplicate push click reports when a notification opens the app from a closed state.

## [0.1.0-stage] - 2026-06-02

### Added

- Initial Flutter SDK implementation.
- Event collection compatible with the Meiro mobile event endpoint.
- Persistent anonymous identity, session management, app lifecycle events, screen tracking observer, and link/custom events.
- Offline event queue with 24-hour retention and connectivity-triggered sync.
- Firebase Cloud Messaging token tracking and Meiro notification receive/click handling.
- Audience WBS API client.
