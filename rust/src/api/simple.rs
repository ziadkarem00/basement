use base64::Engine;
use image::ImageDecoder;
use rand::Rng;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ImageError {
    NotAnImage,
    IsGif,
    TooBig,
    DecodeFailed,
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

#[flutter_rust_bridge::frb(sync)]
pub fn generate_room_code() -> String {
    let code: u32 = rand::thread_rng().gen_range(10000..=99999);
    code.to_string()
}

#[flutter_rust_bridge::frb(sync)]
pub fn clean_name(input: String) -> Option<String> {
    let collapsed = input
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");

    if collapsed.is_empty() {
        return None;
    }

    let truncated: String = collapsed.chars().take(20).collect();
    if truncated.is_empty() {
        None
    } else {
        Some(truncated)
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn is_valid_code(input: String) -> bool {
    input.len() == 5
        && input.chars().all(|c| c.is_ascii_digit())
        && !input.starts_with('0')
}

pub fn process_image(bytes: Vec<u8>) -> Result<String, ImageError> {
    // Magic bytes check
    // GIF: GIF87a or GIF89a
    if bytes.starts_with(b"GIF87a") || bytes.starts_with(b"GIF89a") {
        return Err(ImageError::IsGif);
    }

    let is_jpeg = bytes.starts_with(&[0xFF, 0xD8, 0xFF]);
    let is_png = bytes.starts_with(&[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    let is_webp = bytes.len() >= 12 && &bytes[0..4] == b"RIFF" && &bytes[8..12] == b"WEBP";

    if !is_jpeg && !is_png && !is_webp {
        return Err(ImageError::NotAnImage);
    }

    // Decode and apply EXIF orientation
    let cursor = std::io::Cursor::new(&bytes);
    let reader = image::ImageReader::new(cursor)
        .with_guessed_format()
        .map_err(|_| ImageError::DecodeFailed)?;

    let mut decoder = reader.into_decoder().map_err(|_| ImageError::DecodeFailed)?;
    let orientation = decoder
        .orientation()
        .unwrap_or(image::metadata::Orientation::NoTransforms);

    let mut dynamic =
        image::DynamicImage::from_decoder(decoder).map_err(|_| ImageError::DecodeFailed)?;
    dynamic.apply_orientation(orientation);

    // Resize to max 1024px wide with Lanczos3 if wider
    if dynamic.width() > 1024 {
        let new_height = ((1024 as u64 * dynamic.height() as u64) / dynamic.width() as u64).max(1) as u32;
        dynamic = dynamic.resize_exact(1024, new_height, image::imageops::FilterType::Lanczos3);
    }

    // Flatten transparency on white
    let rgba = dynamic.to_rgba8();
    let mut rgb = image::RgbImage::new(rgba.width(), rgba.height());
    for (x, y, pixel) in rgba.enumerate_pixels() {
        let [r, g, b, a] = pixel.0;
        if a == 255 {
            rgb.put_pixel(x, y, image::Rgb([r, g, b]));
        } else if a == 0 {
            rgb.put_pixel(x, y, image::Rgb([255, 255, 255]));
        } else {
            let alpha = a as u32;
            let inv_alpha = 255 - alpha;
            let r_out = ((r as u32 * alpha + 255 * inv_alpha + 127) / 255) as u8;
            let g_out = ((g as u32 * alpha + 255 * inv_alpha + 127) / 255) as u8;
            let b_out = ((b as u32 * alpha + 255 * inv_alpha + 127) / 255) as u8;
            rgb.put_pixel(x, y, image::Rgb([r_out, g_out, b_out]));
        }
    }

    // Encode JPEG quality 60
    let mut jpeg_bytes = Vec::new();
    let mut encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut jpeg_bytes, 60);
    encoder
        .encode(
            rgb.as_raw(),
            rgb.width(),
            rgb.height(),
            image::ExtendedColorType::Rgb8,
        )
        .map_err(|_| ImageError::DecodeFailed)?;

    // If result over 500KB -> ImageError::TooBig
    if jpeg_bytes.len() > 500 * 1024 {
        return Err(ImageError::TooBig);
    }

    Ok(base64::engine::general_purpose::STANDARD.encode(&jpeg_bytes))
}
