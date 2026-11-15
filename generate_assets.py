import subprocess
import os

dest_dir = "/home/alexius/Projects/LinuxiOSBuilder-full-starter/LinuxiOSBuilder/AsunaLiquidGlass"
os.makedirs(dest_dir, exist_ok=True)

# 1. App Icon: Luxurious Liquid Glass Orb with Amber/Peach Warm Glow and Refraction Arc
app_icon_svg = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <defs>
    <!-- Background Canvas: Deep Obsidian -->
    <radialGradient id="spaceDark" cx="50%" cy="40%" r="65%">
      <stop offset="0%" stop-color="#181920"/>
      <stop offset="50%" stop-color="#0E0F14"/>
      <stop offset="100%" stop-color="#07080A"/>
    </radialGradient>

    <!-- Warm Peach / Lavender Ambient Bloom -->
    <radialGradient id="asunaBloom" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#FF9E79" stop-opacity="0.45"/>
      <stop offset="45%" stop-color="#B282F5" stop-opacity="0.25"/>
      <stop offset="100%" stop-color="#000000" stop-opacity="0"/>
    </radialGradient>

    <!-- Liquid Glass Body Fill -->
    <linearGradient id="glassBody" x1="20%" y1="10%" x2="80%" y2="90%">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.22"/>
      <stop offset="35%" stop-color="#FF9E79" stop-opacity="0.12"/>
      <stop offset="70%" stop-color="#8050D0" stop-opacity="0.18"/>
      <stop offset="100%" stop-color="#141828" stop-opacity="0.40"/>
    </linearGradient>

    <!-- Specular Rim Gradient (Fresnel Light) -->
    <linearGradient id="fresnelRim" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.95"/>
      <stop offset="30%" stop-color="#FFCCA8" stop-opacity="0.45"/>
      <stop offset="65%" stop-color="#7B88FF" stop-opacity="0.15"/>
      <stop offset="100%" stop-color="#FFFFFF" stop-opacity="0.65"/>
    </linearGradient>

    <!-- Top Highlight Caustic Arc -->
    <linearGradient id="causticTop" x1="50%" y1="0%" x2="50%" y2="100%">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.85"/>
      <stop offset="100%" stop-color="#FFFFFF" stop-opacity="0.0"/>
    </linearGradient>

    <!-- Sparkling Star Gradient -->
    <linearGradient id="starGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FFFFFF"/>
      <stop offset="40%" stop-color="#FFBE98"/>
      <stop offset="80%" stop-color="#C092FF"/>
      <stop offset="100%" stop-color="#69B8FF"/>
    </linearGradient>
  </defs>

  <!-- Dark Background -->
  <rect width="512" height="512" rx="112" fill="url(#spaceDark)"/>

  <!-- Ambient Glow Behind Orb -->
  <circle cx="256" cy="256" r="210" fill="url(#asunaBloom)"/>

  <!-- Outer Glass Capsule / Orb -->
  <circle cx="256" cy="256" r="170" fill="url(#glassBody)" stroke="url(#fresnelRim)" stroke-width="4.5"/>

  <!-- Top Glass Caustic Crescent Highlight -->
  <ellipse cx="256" cy="140" rx="100" ry="42" fill="url(#causticTop)"/>

  <!-- Bottom Refraction Bounce -->
  <ellipse cx="256" cy="385" rx="85" ry="24" fill="#FFB088" opacity="0.32"/>

  <!-- Asuna 4-point VectorHeart Star in Center -->
  <path d="M 256,135 
           C 256,215 288,256 368,256 
           C 288,256 256,297 256,377 
           C 256,297 224,256 144,256 
           C 224,256 256,215 256,135 Z" 
        fill="url(#starGrad)"/>

  <!-- Secondary Companion Starlet -->
  <path d="M 345,170 
           C 345,195 356,206 381,206 
           C 356,206 345,217 345,242 
           C 345,217 334,206 309,206 
           C 334,206 345,195 345,170 Z" 
        fill="#FFFFFF" opacity="0.9"/>
</svg>"""

with open(f"{dest_dir}/icon.svg", "w") as f:
    f.write(app_icon_svg)

for sz, name in [
    (512, "icon.png"),
    (152, "AppIcon76x76@2x~ipad.png"),
    (167, "AppIcon83.5x83.5@2x~ipad.png"),
    (76, "AppIcon76x76~ipad.png")
]:
    subprocess.run(["rsvg-convert", "-w", str(sz), "-h", str(sz), f"{dest_dir}/icon.svg", "-o", f"{dest_dir}/{name}"])

# 2. Glass UI Vector Icons (White/Light frosted glass style)
icons = {
    # Voice PTT mic
    "btn_mic.svg": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="#FFFFFF" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/>
  <path d="M19 10v2a7 7 0 0 1-14 0v-2"/>
  <line x1="12" y1="19" x2="12" y2="23"/>
  <line x1="8" y1="23" x2="16" y2="23"/>
</svg>""",

    # Recording state mic (Cyan neon pulse)
    "btn_mic_rec.svg": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="#48E5FF" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
  <rect x="9" y="2" width="6" height="12" rx="3" fill="#48E5FF"/>
  <path d="M19 10v2a7 7 0 0 1-14 0v-2"/>
  <line x1="12" y1="19" x2="12" y2="23"/>
  <line x1="8" y1="23" x2="16" y2="23"/>
</svg>""",

    # Live Mode / Speech Orb button (Peach/Lavender ring)
    "btn_live.svg": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="#FF9E79" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
  <circle cx="12" cy="12" r="10" stroke="#FF9E79"/>
  <circle cx="12" cy="12" r="4.5" fill="#FF9E79" stroke="none"/>
</svg>""",

    # Attachment / image upload clip
    "btn_attach.svg": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="#E6E8EE" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M21.44 11.05l-9.19 9.19a6 6 0 0 1-8.49-8.49l9.19-9.19a4 4 0 0 1 5.66 5.66l-9.2 9.19a2 2 0 0 1-2.83-2.83l8.49-8.48"/>
</svg>""",

    # New chat plus button
    "ic_newchat.svg": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="#FFFFFF" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
  <line x1="12" y1="5" x2="12" y2="19"/>
  <line x1="5" y1="12" x2="19" y2="12"/>
</svg>""",

    # Glass gear settings icon
    "ic_settings.svg": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="#E6E8EE" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <circle cx="12" cy="12" r="3"/>
  <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z"/>
</svg>"""
}

for name, svg in icons.items():
    svg_path = f"{dest_dir}/{name}"
    with open(svg_path, "w") as f:
        f.write(svg)
    base = name.replace(".svg", "")
    subprocess.run(["rsvg-convert", "-w", "28", "-h", "28", svg_path, "-o", f"{dest_dir}/{base}.png"])
    subprocess.run(["rsvg-convert", "-w", "56", "-h", "56", svg_path, "-o", f"{dest_dir}/{base}@2x.png"])

print("Asuna Liquid Glass UI assets successfully generated in", dest_dir)
