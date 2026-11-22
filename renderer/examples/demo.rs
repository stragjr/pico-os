//! Draws a themed phone screen twice, light and dark, from one seed color.
//! Run with: cargo run --release --example demo -- out.png

use pico_renderer::{png, Canvas, Rect, Rgb, Scheme};

const W: usize = 540; // half of the OnePlus 6 panel width
const H: usize = 1140;
const GAP: usize = 40;

fn text_bar(cv: &mut Canvas, x: f32, y: f32, w: f32, c: Rgb) {
    cv.fill_rrect(Rect::new(x, y, w, 14.0), 7.0, c);
}

fn draw_screen(cv: &mut Canvas, ox: f32, s: &Scheme) {
    let w = W as f32;
    let h = H as f32;
    cv.fill_rrect(Rect::new(ox, 0.0, w, h), 0.0, s.surface);

    // Top app bar placeholder with a title bar.
    text_bar(cv, ox + 40.0, 96.0, 220.0, s.on_surface);
    cv.fill_circle(ox + w - 72.0, 103.0, 24.0, s.primary_container);

    // Elevated card.
    let card = Rect::new(ox + 24.0, 170.0, w - 48.0, 280.0);
    cv.shadow(card.offset(0.0, 8.0), 28.0, 28.0, 0.22);
    cv.fill_rrect(card, 28.0, s.surface_container_high);
    cv.fill_circle(ox + 84.0, 240.0, 36.0, s.primary_container);
    text_bar(cv, ox + 144.0, 222.0, 200.0, s.on_surface);
    text_bar(cv, ox + 144.0, 252.0, 140.0, s.on_surface_variant);
    text_bar(cv, ox + 56.0, 330.0, w - 112.0, s.on_surface_variant);
    text_bar(cv, ox + 56.0, 360.0, w - 190.0, s.on_surface_variant);

    // Buttons: filled, tonal, outlined (full pill shape).
    let by = 490.0;
    let filled = Rect::new(ox + 24.0, by, 150.0, 64.0);
    cv.fill_rrect(filled, 32.0, s.primary);
    text_bar(cv, filled.x + 40.0, by + 25.0, 70.0, s.on_primary);
    let tonal = Rect::new(ox + 190.0, by, 150.0, 64.0);
    cv.fill_rrect(tonal, 32.0, s.secondary_container);
    text_bar(cv, tonal.x + 40.0, by + 25.0, 70.0, s.on_secondary_container);
    let outlined = Rect::new(ox + 356.0, by, 160.0, 64.0);
    cv.stroke_rrect(outlined, 32.0, 2.0, s.outline);
    text_bar(cv, outlined.x + 45.0, by + 25.0, 70.0, s.primary);

    // Switches: on and off.
    let on = Rect::new(ox + 40.0, 600.0, 104.0, 64.0);
    cv.fill_rrect(on, 32.0, s.primary);
    cv.fill_circle(on.x + on.w - 32.0, on.y + 32.0, 22.0, s.on_primary);
    let off = Rect::new(ox + 176.0, 600.0, 104.0, 64.0);
    cv.fill_rrect(off, 32.0, s.surface_container);
    cv.stroke_rrect(off, 32.0, 3.0, s.outline);
    cv.fill_circle(off.x + 32.0, off.y + 32.0, 14.0, s.outline);

    // List rows.
    for i in 0..3 {
        let y = 720.0 + i as f32 * 92.0;
        cv.fill_circle(ox + 68.0, y + 32.0, 28.0, s.primary_container);
        text_bar(cv, ox + 120.0, y + 14.0, 230.0, s.on_surface);
        text_bar(cv, ox + 120.0, y + 42.0, 160.0, s.on_surface_variant);
    }

    // Floating action button.
    let fab = Rect::new(ox + w - 136.0, h - 330.0, 104.0, 104.0);
    cv.shadow(fab.offset(0.0, 6.0), 30.0, 22.0, 0.25);
    cv.fill_rrect(fab, 30.0, s.tertiary_container);
    cv.fill_rrect(Rect::new(fab.x + 36.0, fab.y + 49.0, 32.0, 6.0), 3.0, s.on_tertiary_container);
    cv.fill_rrect(Rect::new(fab.x + 49.0, fab.y + 36.0, 6.0, 32.0), 3.0, s.on_tertiary_container);

    // Navigation bar with an active indicator pill.
    let nav = Rect::new(ox, h - 180.0, w, 180.0);
    cv.fill_rrect(nav, 0.0, s.surface_container);
    let step = w / 4.0;
    cv.fill_rrect(Rect::new(ox + step * 0.5 - 56.0, nav.y + 24.0, 112.0, 64.0), 32.0, s.secondary_container);
    for i in 0..4 {
        let cx = ox + step * (i as f32 + 0.5);
        let c = if i == 0 { s.on_secondary_container } else { s.on_surface_variant };
        cv.fill_circle(cx, nav.y + 56.0, 12.0, c);
        text_bar(cv, cx - 28.0, nav.y + 108.0, 56.0, c);
    }

    // Gesture bar.
    cv.fill_rrect(Rect::new(ox + w / 2.0 - 72.0, h - 28.0, 144.0, 8.0), 4.0, s.on_surface);
}

fn main() {
    let out = std::env::args().nth(1).unwrap_or_else(|| "renderer-demo.png".to_string());
    let seed = Rgb::from_hex(0x6750A4);
    let light = Scheme::from_seed(seed, false);
    let dark = Scheme::from_seed(seed, true);

    let mut cv = Canvas::new(W * 2 + GAP, H, Rgb::new(0x20, 0x20, 0x20));
    draw_screen(&mut cv, 0.0, &light);
    draw_screen(&mut cv, (W + GAP) as f32, &dark);

    png::write_rgb(&out, cv.width, cv.height, &cv.rgb).expect("could not write the PNG");
    println!("wrote {} ({}x{})", out, cv.width, cv.height);
}
