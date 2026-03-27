// generate_icon.swift
// NoteNous App Icon Concept & Generation Guide
//
// This file describes the NoteNous app icon design concept.
// It is NOT compiled as part of the app target — it serves as a reference
// for generating the actual icon asset.
//
// === ICON CONCEPT ===
//
// Shape: macOS-standard rounded rectangle (squircle)
// Background: Dark charcoal gradient (#1C1C1E to #2C2C2E), subtle radial from center
//
// Foreground: A stylized "N" constructed from connected nodes and edges:
//   - 5 circular nodes (dots) arranged to form the letter "N"
//     - Bottom-left node (start of N)
//     - Top-left node
//     - Center node (where the diagonal crosses)
//     - Bottom-right node (end of diagonal)
//     - Top-right node (end of N)
//   - Lines connecting the nodes trace the N shape
//   - Each node has a subtle glow/halo effect
//
// Color Palette:
//   - Nodes: Warm amber/gold (#F5A623) with soft glow (#F5A623 at 30% opacity)
//   - Connecting lines: Gold gradient from #D4942A to #F5C463, 2pt stroke
//   - Optional: 2-3 faint secondary nodes floating nearby (smaller, 40% opacity)
//     to suggest a broader knowledge graph extending beyond the N
//
// Symbolism:
//   - "N" = NoteNous
//   - Connected nodes = knowledge graph / linked notes
//   - Neural network aesthetic = "nous" (Greek for mind/intellect)
//   - Warm gold on dark = premium, focused, intellectual
//
// === SIZES NEEDED (macOS) ===
//
// 16x16 @1x, 16x16 @2x (32px)
// 32x32 @1x, 32x32 @2x (64px)
// 128x128 @1x, 128x128 @2x (256px)
// 256x256 @1x, 256x256 @2x (512px)
// 512x512 @1x, 512x512 @2x (1024px)
//
// Design at 1024x1024 and scale down.
//
// === GENERATION OPTIONS ===
//
// 1. Use an image editor (Figma, Sketch, Photoshop) to create at 1024x1024
// 2. Export all required sizes and add filenames to Contents.json
// 3. Alternatively, use a Swift Playground with CGContext to render programmatically
//
// For now, the app uses the default macOS app icon until the asset is provided.
