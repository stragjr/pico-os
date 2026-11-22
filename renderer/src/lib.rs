//! Pico renderer, prototype stage.
//!
//! This crate is a CPU reference implementation of the drawing model the GPU
//! renderer will follow: signed-distance-field shapes, tonal color from a seed,
//! and Material-style surfaces. It has no dependencies so it builds anywhere.
//! The Vulkan/GLES backend replaces `canvas` later; `color` carries over as is.

pub mod canvas;
pub mod color;
pub mod png;

pub use canvas::{Canvas, Rect};
pub use color::{Rgb, Scheme, TonalPalette};
