# Poll Call brand

**Name.** Poll Call, like a roll call. It keeps calling your name until you vote,
then stops. Tagline: *We'll keep calling until you vote.*

**Mark.** A marigold circle with a check that breaks out of it. Inside the circle
the check is teal; where it escapes, it turns marigold. Flat, no gradients or
shadows, readable down to the smallest Settings icon.

**Nonpartisan by design.** No red-versus-blue anywhere.

## Color

| Name | Hex | Use |
|---|---|---|
| Ink teal | `#0B3B3C` (dark mode `#5CC6B4`) | Headlines, toggles, links, Election Day pins, icon and launch background |
| Marigold | `#F5B301` | The mark, the I voted button, early voting pins. Only for "do the thing" |
| On marigold | `#0B3B3C` | Text and icons on marigold (never white; it fails contrast) |
| Slate | `#5B6B73` | Drop boxes and other secondary items |

## Type

SF Pro Rounded throughout, set once at the app root. Headlines in Black weight.

## Voice

Plain, specific, never guilt-trippy, never partisan.

- Useful and true: "Polls close at 7:00 PM. If you're in line at closing time, stay in line."
- Actions named by what happens: "I voted", "Remind me to vote", "Undo".
- After voting: "You voted. We'll stop calling."

## Assets

- `AppIcon-1024.png`: single-size iOS icon, no alpha
- `LaunchMark`: the mark on transparent, centered on the teal launch screen
- `Brand.swift`: colors, `PollCallMark`, `Wordmark`, `IVotedButton`, `IVotedSticker`, `VotedBadge`
