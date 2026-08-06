# Agent Box Icon Composer import kit

The import artwork matches the three-card mark on the Agent Box onboarding screen. Each SVG uses a
1024×1024 canvas. The source layers are flat, opaque, and free of masks, shadows, blur, gradients,
and glass effects. Add those properties in Icon Composer.

## Import

1. Open Icon Composer and create a document named `AppIcon`.
2. In the Document inspector, select **iOS Only** and turn off watchOS.
3. In Finder, open the `Import` folder next to this file.
4. Drag the `01-back`, `02-middle`, and `03-front` folders into the Icon Composer sidebar.
5. Keep the groups in number order. `01-back` is the bottom group and `03-front` is the top group.
6. Do not import files from the `Reference` folder. They show the intended result only.

## Suggested appearance

Use the same geometry in all appearance modes. Let Icon Composer apply the enclosure mask.

| Part        | Default                               | Dark                                  | Mono                  |
| ----------- | ------------------------------------- | ------------------------------------- | --------------------- |
| Background  | Blue gradient, `#54B7FF` to `#0066D6` | Navy gradient, `#163F70` to `#061426` | Automatic system tint |
| Back card   | White, about 48% visible              | White, about 44% visible              | About 34% visible     |
| Middle card | White, about 72% visible              | White, about 70% visible              | About 62% visible     |
| Front card  | White, 100% visible                   | White, 100% visible                   | 100% visible          |

Start with the default Liquid Glass settings. Keep the three card groups separate so the system can
give them depth. Use an automatic specular highlight and low refraction. Do not add a manual shadow
or blur. Check that every card edge stays clear in Default, Dark, and Mono previews.

Save the completed document as `AppIcon.icon`. The active document is stored at
`AgentBox/Resources/AppIcon.icon`, beside `Assets.xcassets`. The target's App Icon value is
`AppIcon`.
