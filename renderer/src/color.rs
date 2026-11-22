//! Color: sRGB, OKLab/OKLCH, and Material-style tonal palettes and schemes.
//!
//! Tones follow Material's meaning (0 = black, 100 = white, roughly CIELAB L*),
//! but the palette is generated in OKLCH. This is a stand-in for Google's HCT
//! color space: close in spirit, not identical in output.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Rgb {
    pub r: u8,
    pub g: u8,
    pub b: u8,
}

impl Rgb {
    pub const fn new(r: u8, g: u8, b: u8) -> Self {
        Rgb { r, g, b }
    }

    pub const fn from_hex(hex: u32) -> Self {
        Rgb::new((hex >> 16) as u8, (hex >> 8) as u8, hex as u8)
    }

    /// WCAG relative luminance, 0.0 (black) to 1.0 (white).
    pub fn luminance(self) -> f32 {
        0.2126 * srgb_to_linear(self.r) + 0.7152 * srgb_to_linear(self.g) + 0.0722 * srgb_to_linear(self.b)
    }
}

/// WCAG contrast ratio between two colors, 1.0 to 21.0.
pub fn contrast_ratio(a: Rgb, b: Rgb) -> f32 {
    let (la, lb) = (a.luminance(), b.luminance());
    let (hi, lo) = if la > lb { (la, lb) } else { (lb, la) };
    (hi + 0.05) / (lo + 0.05)
}

fn srgb_to_linear(u: u8) -> f32 {
    let c = u as f32 / 255.0;
    if c <= 0.04045 {
        c / 12.92
    } else {
        ((c + 0.055) / 1.055).powf(2.4)
    }
}

fn linear_to_srgb(x: f32) -> f32 {
    let x = x.clamp(0.0, 1.0);
    if x <= 0.0031308 {
        12.92 * x
    } else {
        1.055 * x.powf(1.0 / 2.4) - 0.055
    }
}

#[derive(Clone, Copy, Debug)]
pub struct Oklch {
    pub l: f32,
    pub c: f32,
    /// Hue in degrees, 0 to 360.
    pub h: f32,
}

pub fn rgb_to_oklch(c: Rgb) -> Oklch {
    let (r, g, b) = (srgb_to_linear(c.r), srgb_to_linear(c.g), srgb_to_linear(c.b));
    let l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b).cbrt();
    let m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b).cbrt();
    let s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b).cbrt();
    let big_l = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
    let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
    let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
    let chroma = (a * a + bb * bb).sqrt();
    let mut hue = bb.atan2(a).to_degrees();
    if hue < 0.0 {
        hue += 360.0;
    }
    Oklch { l: big_l, c: chroma, h: hue }
}

fn oklch_to_linear(l: f32, c: f32, h_deg: f32) -> [f32; 3] {
    let h = h_deg.to_radians();
    let (a, b) = (c * h.cos(), c * h.sin());
    let l_ = l + 0.3963377774 * a + 0.2158037573 * b;
    let m_ = l - 0.1055613458 * a - 0.0638541728 * b;
    let s_ = l - 0.0894841775 * a - 1.2914855480 * b;
    let (l3, m3, s3) = (l_ * l_ * l_, m_ * m_ * m_, s_ * s_ * s_);
    [
        4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
        -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
        -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3,
    ]
}

fn in_gamut(rgb: [f32; 3]) -> bool {
    rgb.iter().all(|v| *v >= -0.0002 && *v <= 1.0002)
}

/// Convert OKLCH to sRGB, lowering chroma until the color fits in gamut.
pub fn oklch_to_rgb(l: f32, c: f32, h_deg: f32) -> Rgb {
    let l = l.clamp(0.0, 1.0);
    let mut lin = oklch_to_linear(l, c, h_deg);
    if !in_gamut(lin) {
        let (mut lo, mut hi) = (0.0_f32, c);
        for _ in 0..24 {
            let mid = 0.5 * (lo + hi);
            if in_gamut(oklch_to_linear(l, mid, h_deg)) {
                lo = mid;
            } else {
                hi = mid;
            }
        }
        lin = oklch_to_linear(l, lo, h_deg);
    }
    let to_u8 = |x: f32| (linear_to_srgb(x) * 255.0).round() as u8;
    Rgb::new(to_u8(lin[0]), to_u8(lin[1]), to_u8(lin[2]))
}

/// Material tone (0 to 100) to OKLab lightness, via CIELAB L* -> Y -> cube root.
fn tone_to_lightness(tone: u8) -> f32 {
    let t = tone.min(100) as f32;
    let y = if t > 8.0 { ((t + 16.0) / 116.0).powi(3) } else { t / 903.3 };
    y.cbrt()
}

#[derive(Clone, Copy, Debug)]
pub struct TonalPalette {
    pub hue: f32,
    pub chroma: f32,
}

impl TonalPalette {
    pub fn new(hue: f32, chroma: f32) -> Self {
        TonalPalette { hue, chroma }
    }

    pub fn tone(&self, tone: u8) -> Rgb {
        oklch_to_rgb(tone_to_lightness(tone), self.chroma, self.hue)
    }
}

/// The color roles the shell and apps draw with. A subset of Material 3 roles.
#[derive(Clone, Copy, Debug)]
pub struct Scheme {
    pub primary: Rgb,
    pub on_primary: Rgb,
    pub primary_container: Rgb,
    pub on_primary_container: Rgb,
    pub secondary_container: Rgb,
    pub on_secondary_container: Rgb,
    pub tertiary_container: Rgb,
    pub on_tertiary_container: Rgb,
    pub surface: Rgb,
    pub surface_container: Rgb,
    pub surface_container_high: Rgb,
    pub on_surface: Rgb,
    pub on_surface_variant: Rgb,
    pub outline: Rgb,
}

impl Scheme {
    /// Build a light or dark scheme from a single seed color.
    pub fn from_seed(seed: Rgb, dark: bool) -> Self {
        let s = rgb_to_oklch(seed);
        let primary = TonalPalette::new(s.h, s.c.clamp(0.08, 0.20));
        let secondary = TonalPalette::new(s.h, primary.chroma * 0.35);
        let tertiary = TonalPalette::new((s.h + 60.0) % 360.0, primary.chroma.max(0.10) * 0.6);
        let neutral = TonalPalette::new(s.h, 0.012);
        let variant = TonalPalette::new(s.h, 0.025);

        if dark {
            Scheme {
                primary: primary.tone(80),
                on_primary: primary.tone(20),
                primary_container: primary.tone(30),
                on_primary_container: primary.tone(90),
                secondary_container: secondary.tone(30),
                on_secondary_container: secondary.tone(90),
                tertiary_container: tertiary.tone(30),
                on_tertiary_container: tertiary.tone(90),
                surface: neutral.tone(6),
                surface_container: neutral.tone(12),
                surface_container_high: neutral.tone(17),
                on_surface: neutral.tone(90),
                on_surface_variant: variant.tone(80),
                outline: variant.tone(60),
            }
        } else {
            Scheme {
                primary: primary.tone(40),
                on_primary: primary.tone(100),
                primary_container: primary.tone(90),
                on_primary_container: primary.tone(10),
                secondary_container: secondary.tone(90),
                on_secondary_container: secondary.tone(10),
                tertiary_container: tertiary.tone(90),
                on_tertiary_container: tertiary.tone(10),
                surface: neutral.tone(98),
                surface_container: neutral.tone(94),
                surface_container_high: neutral.tone(92),
                on_surface: neutral.tone(10),
                on_surface_variant: variant.tone(30),
                outline: variant.tone(50),
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn white_has_full_lightness() {
        let w = rgb_to_oklch(Rgb::new(255, 255, 255));
        assert!((w.l - 1.0).abs() < 0.01, "L was {}", w.l);
        assert!(w.c < 0.01);
    }

    #[test]
    fn tone_extremes_are_black_and_white() {
        let p = TonalPalette::new(300.0, 0.15);
        assert!(p.tone(0).luminance() < 0.01);
        assert!(p.tone(100).luminance() > 0.95);
    }

    #[test]
    fn in_gamut_color_round_trips() {
        let c = Rgb::from_hex(0x6750A4);
        let o = rgb_to_oklch(c);
        let back = oklch_to_rgb(o.l, o.c, o.h);
        let d = |a: u8, b: u8| (a as i32 - b as i32).abs();
        assert!(d(c.r, back.r) <= 2 && d(c.g, back.g) <= 2 && d(c.b, back.b) <= 2, "{:?} -> {:?}", c, back);
    }

    #[test]
    fn tones_follow_material_lightness() {
        // Tone 50 should land near mid luminance (CIELAB L* 50 is Y = 0.184).
        let p = TonalPalette::new(0.0, 0.0);
        let y = p.tone(50).luminance();
        assert!((y - 0.184).abs() < 0.02, "Y was {}", y);
    }

    #[test]
    fn schemes_meet_text_contrast() {
        for seed in [0x6750A4u32, 0x006A6A, 0xB3261E, 0x2E7D32, 0x1565C0] {
            for dark in [false, true] {
                let s = Scheme::from_seed(Rgb::from_hex(seed), dark);
                let pairs = [
                    (s.on_primary, s.primary),
                    (s.on_primary_container, s.primary_container),
                    (s.on_secondary_container, s.secondary_container),
                    (s.on_tertiary_container, s.tertiary_container),
                    (s.on_surface, s.surface),
                    (s.on_surface, s.surface_container_high),
                    (s.on_surface_variant, s.surface_container),
                ];
                for (i, (fg, bg)) in pairs.iter().enumerate() {
                    let ratio = contrast_ratio(*fg, *bg);
                    assert!(ratio >= 4.5, "seed {:06X} dark {} pair {} contrast {:.2}", seed, dark, i, ratio);
                }
            }
        }
    }
}
