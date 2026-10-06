# eig_fonts -- register the EIG brand fonts for ggplot/ragg rendering
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - how have real hourly wages evolved across percentiles, age bins, and generations from 1982 through present?

# Sourced by the figure scripts via
#   source(here::here("code", "_utils", "eig_fonts.R"))
# after load_palette.R. It registers the EIG brand fonts from
# code/_utils/fonts/ (Galaxie Polaris for body text, Tiempos Text for
# titles) so ragg can render them by family name. The font files are
# commercially licensed and are not distributed with this repository
# (the directory is gitignored); without them every figure renders in
# the sans fallback described below.
#
# The script populates four objects in the CALLING environment:
#   eig_font_body_chr        -- body/axis/legend/caption family name
#   eig_font_title_chr       -- figure-title family name
#   eig_png_device           -- graphics device to pass to ggplot2::ggsave()
#                               (ragg::agg_png when available, else "png")
#   eig_fonts_registered_bool-- TRUE if the brand fonts registered cleanly
#
# Fallback: if systemfonts/ragg are unavailable or the .otf files are
# missing, the family names fall back to "sans" (the documented
# Arial/Helvetica fallback) and rendering uses the default png device, so
# every figure still builds. No custom functions are defined.

# Defaults assume the fallback path; overwritten below on success.
eig_font_body_chr         <- "sans"
eig_font_title_chr        <- "sans"
eig_fonts_registered_bool <- FALSE
eig_png_device            <- "png"

# ragg renders systemfonts-registered fonts; without it, registration
# does not help the default png device, so gate the whole block on both.
if (requireNamespace("systemfonts", quietly = TRUE) &&
    requireNamespace("ragg", quietly = TRUE)) {

  eig_font_dir_chr <- here::here("code", "_utils", "fonts")

  eig_body_book_chr  <- fs::path(eig_font_dir_chr, "GalaxiePolaris-Book.otf")
  eig_body_bold_chr  <- fs::path(eig_font_dir_chr, "GalaxiePolaris-Bold.otf")
  eig_title_reg_chr  <- fs::path(eig_font_dir_chr, "TiemposText-Regular.otf")
  eig_title_semi_chr <- fs::path(eig_font_dir_chr, "TiemposText-Semibold.otf")
  eig_title_ital_chr <- fs::path(eig_font_dir_chr, "TiemposText-RegularItalic.otf")

  eig_font_files_present_bool <- all(fs::file_exists(c(
    eig_body_book_chr, eig_body_bold_chr,
    eig_title_reg_chr, eig_title_semi_chr
  )))

  if (eig_font_files_present_bool) {
    # register_font maps Semibold to the "bold" slot so
    # element_text(face = "bold") on the Tiempos title resolves to the
    # Semibold cut the EIG guide specifies. Wrapped in try(): a
    # registration failure must not abort the figure build.
    eig_font_try <- try(
      {
        systemfonts::register_font(
          name  = "Galaxie Polaris",
          plain = eig_body_book_chr,
          bold  = eig_body_bold_chr
        )
        systemfonts::register_font(
          name   = "Tiempos Text",
          plain  = eig_title_reg_chr,
          bold   = eig_title_semi_chr,
          italic = eig_title_ital_chr
        )
      },
      silent = TRUE
    )

    if (!inherits(eig_font_try, "try-error")) {
      eig_font_body_chr         <- "Galaxie Polaris"
      eig_font_title_chr        <- "Tiempos Text"
      eig_png_device            <- ragg::agg_png
      eig_fonts_registered_bool <- TRUE
    }
  }
}

message(
  "eig_fonts.R -- ",
  if (eig_fonts_registered_bool) {
    "registered EIG brand fonts (Galaxie Polaris body, Tiempos Text titles); ragg device active."
  } else {
    "EIG brand fonts unavailable; falling back to 'sans' and the default png device."
  }
)
