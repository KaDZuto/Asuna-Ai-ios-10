import subprocess

dest = "/home/alexius/Projects/LinuxiOSBuilder-full-starter/LinuxiOSBuilder/AsunaLiquidGlass"

# 1. Idle warm peach sphere with realistic glass caustics
orb_idle_svg = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 160 160" width="160" height="160">
  <defs>
    <radialGradient id="sphereCore" cx="45%" cy="35%" r="60%">
      <stop offset="0%" stop-color="#FFC59E"/>
      <stop offset="45%" stop-color="#D97A48"/>
      <stop offset="85%" stop-color="#803818"/>
      <stop offset="100%" stop-color="#3D1808"/>
    </radialGradient>
    <linearGradient id="rimFresnel" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.95"/>
      <stop offset="50%" stop-color="#FF9E79" stop-opacity="0.3"/>
      <stop offset="100%" stop-color="#FFFFFF" stop-opacity="0.7"/>
    </linearGradient>
    <linearGradient id="causticTop" x1="50%" y1="0%" x2="50%" y2="100%">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.85"/>
      <stop offset="100%" stop-color="#FFFFFF" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <!-- Outer Sphere -->
  <circle cx="80" cy="80" r="74" fill="url(#sphereCore)" stroke="url(#rimFresnel)" stroke-width="3"/>
  <!-- Top Highlight Arc -->
  <ellipse cx="80" cy="38" rx="42" ry="18" fill="url(#causticTop)"/>
  <!-- Mic silhouette centered inside glass -->
  <g transform="translate(56, 52) scale(2.0)" fill="none" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
    <path d="M12 2a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3z"/>
    <path d="M19 10v1a7 7 0 0 1-14 0v-1"/>
    <line x1="12" y1="18" x2="12" y2="22"/>
    <line x1="8" y1="22" x2="16" y2="22"/>
  </g>
</svg>"""

# 2. Recording / Listening cyan sphere
orb_rec_svg = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 160 160" width="160" height="160">
  <defs>
    <radialGradient id="sphereRec" cx="45%" cy="35%" r="60%">
      <stop offset="0%" stop-color="#AAFFFF"/>
      <stop offset="45%" stop-color="#28C8F0"/>
      <stop offset="85%" stop-color="#0E6090"/>
      <stop offset="100%" stop-color="#052035"/>
    </radialGradient>
    <linearGradient id="rimFresnelRec" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="1.0"/>
      <stop offset="50%" stop-color="#48E5FF" stop-opacity="0.5"/>
      <stop offset="100%" stop-color="#FFFFFF" stop-opacity="0.85"/>
    </linearGradient>
  </defs>
  <circle cx="80" cy="80" r="74" fill="url(#sphereRec)" stroke="url(#rimFresnelRec)" stroke-width="4"/>
  <ellipse cx="80" cy="38" rx="42" ry="18" fill="#FFFFFF" opacity="0.8"/>
  <g transform="translate(56, 52) scale(2.0)" fill="none" stroke="#FFFFFF" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
    <rect x="9" y="2" width="6" height="10" rx="3" fill="#FFFFFF"/>
    <path d="M19 10v1a7 7 0 0 1-14 0v-1"/>
    <line x1="12" y1="18" x2="12" y2="22"/>
    <line x1="8" y1="22" x2="16" y2="22"/>
  </g>
</svg>"""

with open(f"{dest}/orb_ptt.svg", "w") as f:
    f.write(orb_idle_svg)
with open(f"{dest}/orb_ptt_rec.svg", "w") as f:
    f.write(orb_rec_svg)

subprocess.run(["rsvg-convert", "-w", "80", "-h", "80", f"{dest}/orb_ptt.svg", "-o", f"{dest}/orb_ptt.png"])
subprocess.run(["rsvg-convert", "-w", "160", "-h", "160", f"{dest}/orb_ptt.svg", "-o", f"{dest}/orb_ptt@2x.png"])

subprocess.run(["rsvg-convert", "-w", "80", "-h", "80", f"{dest}/orb_ptt_rec.svg", "-o", f"{dest}/orb_ptt_rec.png"])
subprocess.run(["rsvg-convert", "-w", "160", "-h", "160", f"{dest}/orb_ptt_rec.svg", "-o", f"{dest}/orb_ptt_rec@2x.png"])

print("Liquid glass orb buttons generated!")
