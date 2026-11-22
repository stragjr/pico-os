//! CPU canvas with anti-aliased signed-distance-field shapes.
//!
//! The GPU renderer draws the same shapes with the same distance function in a
//! fragment shader; this version exists so the visuals can be developed and
//! tested on any machine.

use crate::color::Rgb;

#[derive(Clone, Copy, Debug)]
pub struct Rect {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
}

impl Rect {
    pub fn new(x: f32, y: f32, w: f32, h: f32) -> Self {
        Rect { x, y, w, h }
    }

    pub fn inflate(self, d: f32) -> Self {
        Rect::new(self.x - d, self.y - d, self.w + 2.0 * d, self.h + 2.0 * d)
    }

    pub fn offset(self, dx: f32, dy: f32) -> Self {
        Rect::new(self.x + dx, self.y + dy, self.w, self.h)
    }
}

/// Signed distance from a point to a rounded rectangle: negative inside,
/// positive outside, zero on the edge.
pub fn sdf_rounded_rect(px: f32, py: f32, r: Rect, radius: f32) -> f32 {
    let hw = r.w * 0.5;
    let hh = r.h * 0.5;
    let radius = radius.min(hw).min(hh).max(0.0);
    let qx = (px - (r.x + hw)).abs() - (hw - radius);
    let qy = (py - (r.y + hh)).abs() - (hh - radius);
    let (ox, oy) = (qx.max(0.0), qy.max(0.0));
    (ox * ox + oy * oy).sqrt() + qx.max(qy).min(0.0) - radius
}

pub struct Canvas {
    pub width: usize,
    pub height: usize,
    /// Packed RGB, 3 bytes per pixel, row by row.
    pub rgb: Vec<u8>,
}

impl Canvas {
    pub fn new(width: usize, height: usize, background: Rgb) -> Self {
        let mut rgb = Vec::with_capacity(width * height * 3);
        for _ in 0..width * height {
            rgb.extend_from_slice(&[background.r, background.g, background.b]);
        }
        Canvas { width, height, rgb }
    }

    pub fn get(&self, x: usize, y: usize) -> Rgb {
        let i = (y * self.width + x) * 3;
        Rgb::new(self.rgb[i], self.rgb[i + 1], self.rgb[i + 2])
    }

    fn blend(&mut self, x: usize, y: usize, c: Rgb, alpha: f32) {
        if alpha <= 0.0 {
            return;
        }
        let a = alpha.min(1.0);
        let i = (y * self.width + x) * 3;
        for (k, v) in [c.r, c.g, c.b].into_iter().enumerate() {
            let d = self.rgb[i + k] as f32;
            self.rgb[i + k] = (d + (v as f32 - d) * a).round() as u8;
        }
    }

    fn bounds(&self, r: Rect) -> (usize, usize, usize, usize) {
        let x0 = r.x.floor().max(0.0) as usize;
        let y0 = r.y.floor().max(0.0) as usize;
        let x1 = ((r.x + r.w).ceil().max(0.0) as usize).min(self.width);
        let y1 = ((r.y + r.h).ceil().max(0.0) as usize).min(self.height);
        (x0, y0, x1, y1)
    }

    pub fn fill_rrect(&mut self, r: Rect, radius: f32, c: Rgb) {
        self.fill_rrect_alpha(r, radius, c, 1.0);
    }

    pub fn fill_rrect_alpha(&mut self, r: Rect, radius: f32, c: Rgb, alpha: f32) {
        let (x0, y0, x1, y1) = self.bounds(r.inflate(1.0));
        for y in y0..y1 {
            for x in x0..x1 {
                let d = sdf_rounded_rect(x as f32 + 0.5, y as f32 + 0.5, r, radius);
                let coverage = (0.5 - d).clamp(0.0, 1.0);
                self.blend(x, y, c, coverage * alpha);
            }
        }
    }

    /// Outline drawn inside the shape's edge, `width` pixels thick.
    pub fn stroke_rrect(&mut self, r: Rect, radius: f32, width: f32, c: Rgb) {
        let (x0, y0, x1, y1) = self.bounds(r.inflate(1.0));
        for y in y0..y1 {
            for x in x0..x1 {
                let d = sdf_rounded_rect(x as f32 + 0.5, y as f32 + 0.5, r, radius);
                let ring = (d + width * 0.5).abs() - width * 0.5;
                let coverage = (0.5 - ring).clamp(0.0, 1.0);
                self.blend(x, y, c, coverage);
            }
        }
    }

    pub fn fill_circle(&mut self, cx: f32, cy: f32, radius: f32, c: Rgb) {
        let r = Rect::new(cx - radius, cy - radius, radius * 2.0, radius * 2.0);
        self.fill_rrect(r, radius, c);
    }

    /// Soft black shadow: full strength well inside the shape, fading to nothing
    /// `blur` pixels around its edge. Pass the already offset rectangle.
    pub fn shadow(&mut self, r: Rect, radius: f32, blur: f32, alpha: f32) {
        let (x0, y0, x1, y1) = self.bounds(r.inflate(blur));
        for y in y0..y1 {
            for x in x0..x1 {
                let d = sdf_rounded_rect(x as f32 + 0.5, y as f32 + 0.5, r, radius);
                let t = ((d + blur * 0.5) / blur).clamp(0.0, 1.0);
                let falloff = (1.0 - t) * (1.0 - t);
                self.blend(x, y, Rgb::new(0, 0, 0), falloff * alpha);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const BG: Rgb = Rgb::new(255, 255, 255);
    const FG: Rgb = Rgb::new(0, 0, 0);

    #[test]
    fn sdf_signs() {
        let r = Rect::new(10.0, 10.0, 100.0, 50.0);
        assert!(sdf_rounded_rect(60.0, 35.0, r, 12.0) < 0.0);
        assert!(sdf_rounded_rect(200.0, 35.0, r, 12.0) > 0.0);
        assert!(sdf_rounded_rect(10.0, 35.0, r, 12.0).abs() < 1e-3);
    }

    #[test]
    fn rounded_corner_is_cut() {
        let mut cv = Canvas::new(60, 60, BG);
        cv.fill_rrect(Rect::new(10.0, 10.0, 40.0, 40.0), 16.0, FG);
        assert_eq!(cv.get(30, 30), FG);
        assert_eq!(cv.get(10, 10), BG); // square corner would have painted here
        assert_eq!(cv.get(2, 2), BG);
    }

    #[test]
    fn edge_is_antialiased() {
        let mut cv = Canvas::new(40, 40, BG);
        cv.fill_circle(20.0, 20.0, 10.0, FG);
        let mut partial = 0;
        for y in 0..40 {
            for x in 0..40 {
                let p = cv.get(x, y);
                if p != BG && p != FG {
                    partial += 1;
                }
            }
        }
        assert!(partial > 20, "only {} edge pixels", partial);
    }

    #[test]
    fn stroke_leaves_the_inside_alone() {
        let mut cv = Canvas::new(60, 60, BG);
        cv.stroke_rrect(Rect::new(10.0, 10.0, 40.0, 40.0), 8.0, 2.0, FG);
        assert_eq!(cv.get(30, 30), BG);
        assert_ne!(cv.get(10, 30), BG);
    }

    #[test]
    fn shadow_fades_with_distance() {
        let mut cv = Canvas::new(100, 100, BG);
        cv.shadow(Rect::new(30.0, 30.0, 40.0, 40.0), 8.0, 16.0, 0.5);
        let near = cv.get(50, 74).r;
        let far = cv.get(50, 95).r;
        assert!(near < far, "near {} far {}", near, far);
        assert_eq!(cv.get(2, 2), BG);
    }
}
