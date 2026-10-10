# 2026-10-10 — One sprite batch, in-place reload, shared actor states

Resolves items 6.1, 6.2 and 6.3 of the October 2026 engine review.

## What changed

- **Renderer (6.1).** One `SpriteBatch` replaces the plain, tinted and filled
  sprite batches, `ShapeBatchQueue`, and the text renderer's two batches.
- **Resources (6.2).** Each asset name has one slot for the life of the
  `ResourceManager`; a reload swaps the value in place.
- **Animation (6.3).** Actors point at shared `ActorState`s instead of
  copying them; flips are `flipX`/`flipY` bools.

## Decisions

**Per-vertex mode, not a second shader.** Each vertex carries a `DrawMode`
byte (texture, mask, fill) next to its rgba8 colour, and one fragment shader
branches on it. Fill sprites, glyph masks, tinted sprites and shapes on the
same texture therefore share a draw call, and the only flush left is a
texture switch. A second program for fill would have brought back a
kind-switch flush for one rarely used feature.

**Shapes draw from a built-in 1x1 white texture** owned by the batch, so a
shape is just a quad in `.texture` mode with a colour.

**R8 font atlas everywhere.** R8/`RED` is core in GL ES 3.0 and WebGL 2, so the
desktop/web split (red vs alpha channel) and its four text shaders are gone.
Bitmap fonts stay RGBA and draw in `.texture` mode, which also means
`drawStringColored` now works with them.

**Fixed attribute locations.** The sprite shader declares
`layout(location = N)`, so the batch sets its VAO up once and a shader reload
only re-looks-up the two uniforms. The index buffer is uploaded once at init,
and each flush orphans a `STREAM_DRAW` buffer before `bufferSubData`.

**The public draw API is unchanged.** `drawSprite`, `drawSpriteColored`,
`drawSpriteFilled`, the rect calls and the four text calls keep their
signatures; they all write into the one batch. The text calls share one
internal glyph loop. Arbitrary rotation, lines and circles were left for
review item 3 rather than folded in here.

**Projection dedupe came along.** `Viewport` owns the raster-ortho helper
(`projection`, `screenProjection`, `applyFullscreen`) and
`windowToFramebuffer`/`windowToLogical`; `Engine` and `InputManager` call
them. `Viewport.compute` picks a scale per policy and centers once; stretch
keeps setting the rect directly so float rounding can't lose a pixel.

**No refcounting at all.** Slots are never freed before the manager
deinits, so `acquire*`, `retain`, `release`, generations, `dirty`,
`reacquire`, `rollbackAdd` and `keepStale` all went, and debug and release
builds free memory the same way. `Sprite.deinit` went too, since a sprite
owns nothing. `AssetManifest.unloadGroup` now only forgets that a group was
loaded; it never freed anything in practice either (clean handles at
refcount 0 were kept).

**`version` replaces `dirty`.** Holders that cache data derived from an
asset (shader uniform/attribute locations, chunk VAOs, `TileMapRenderer`
layers, remzman's level state) remember the `version` they built from and
rebuild when it changes.

**Images re-upload into the same GL texture.** A texture reload calls
`texImage2D` on the existing texture object instead of creating a new one,
so atlas frames and subtextures, which copy the GL id, stay valid. That
removed `Texture.image`. An atlas reload decodes the PNG and validates the
JSON before touching any slot, so a bad file leaves the old atlas drawing,
and a frame dropped from the JSON keeps its last value rather than leaving a
dangling handle.

**Actors keep pointers, plus their own key.** `Actor.addState` stores a
`*const ActorState` and dupes only the lookup key, so remzman-style aliases
(`.name = "left"` for a shared `"red_left"`) still work; `currName` tracks the
alias since it can differ from `currState.name`. The state must outlive the
actor, which the manager guarantees. `FrameSequenceManager.addSeq`/`addState`
re-adds now update in place for the same reason. Sequence JSON keeps its
`"flip"` enum; `Flip.x()`/`.y()` convert it.

## Downstream

remzman (`Level` tracks `map.version`), mazegaze (`getTexture`) and digcraft
(no sprite deinit loop) were ported and build against this. ffme needed
nothing. spritez's two handle-API lines were updated, but spritez doesn't
build on zig 0.17 for unrelated reasons (its `build.zig` and the
nativefiledialog dependency), so that edit is unverified.
