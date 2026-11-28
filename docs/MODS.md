# Oganesson mods (`.ogmod`)

A mod adds **themes, note templates, AI actions and fonts** to Oganesson. It is only data: the app
validates every field and never runs code from a mod.

Install one from **⋯ → Mods → Install**. Remove it from the same screen.

## File layout

An `.ogmod` file is a regular **zip** (rename `.zip` to `.ogmod`) with `mod.json` at its root:

```
my-mod.ogmod
├── mod.json
└── fonts/
    └── Handwriting.ttf      (only if the mod has fonts)
```

Limits: 8 MB per mod, 3 MB per font, up to 12 themes, 40 templates, 20 AI actions and 4 fonts.

## `mod.json`

```json
{
  "format": 1,
  "id": "rafa.autumn",
  "name": "Autumn",
  "author": "Rafa",
  "version": "1.0",
  "description": "Warm colours, a study template and an exam helper.",

  "themes": [
    {
      "id": "autumn",
      "name": "Autumn",
      "description": "Burnt orange and cream",
      "light": {
        "accent": "#C2571A", "onAccent": "#FFFFFF",
        "background": "#FAF3EC", "card": "#FFFCF8",
        "secondary": "#7A665A", "separator": "#EAD8C8",
        "selected": "#F8DCC8", "searchFill": "#F1E6DB", "hover": "#FBF2EA"
      },
      "dark": {
        "accent": "#F29A5B", "onAccent": "#2A1206",
        "background": "#15100C", "card": "#231A14",
        "secondary": "#B09A8C", "separator": "#3D2E25",
        "selected": "#5A3323", "searchFill": "#231A14", "hover": "#2F231B"
      }
    }
  ],

  "templates": [
    {
      "name": "Study session",
      "text": "Study session\n## Goal\n- [ ] Read chapter\n- [ ] Exercises\n## Notes\n"
    }
  ],

  "aiActions": [
    { "name": "Exam questions", "prompt": "Write 5 exam questions about this note, with short answers." }
  ],

  "fonts": [
    { "name": "Handwriting", "file": "fonts/Handwriting.ttf" }
  ]
}
```

### Fields

| Field | Required | Notes |
|---|---|---|
| `format` | yes | Always `1`. |
| `id` | yes | 3–60 characters: lowercase letters, numbers, `.`, `_`, `-`. Installing a mod with the same id updates it. |
| `name` | yes | Up to 60 characters. |
| `author`, `version`, `description` | no | Shown in the Mods screen. |
| `themes[]` | no | `light` and `dark`, each with `accent`, `background`, `card`, `secondary`, `separator` and `selected` as `#RRGGBB`. `onAccent` (default white), `searchFill` and `hover` (default `background`) are optional. They appear in **Theme and colours** (Ctrl+,). |
| `templates[]` | no | `name` and `text` in Markdown (`#`, `-`, `1.`, `- [ ]`, `**bold**`…). The first line is the note title. They appear in **New from template**. |
| `aiActions[]` | no | `name` and `prompt`. They appear as chips in the note's AI button; the prompt is asked about that note. |
| `fonts[]` | no | `name` and `file` (a `.ttf` or `.otf` inside the zip). They appear in **Theme and colours → Font**. |

A mod must contain at least one theme, template, AI action or font.
