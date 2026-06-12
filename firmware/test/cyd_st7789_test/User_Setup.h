// ST7789 driver test — CYD2USB ESP32-2432S028
// Mirrors the witnessmenow reference config but adds explicit dimensions.
// Compare against ILI9341_DRIVER in PadDis/User_Setup.h.

#define USER_SETUP_LOADED

#define ST7789_DRIVER

// Physical dimensions: try portrait-native first (same as ILI9341 config).
// If screen is only partially used, swap to TFT_WIDTH 320 / TFT_HEIGHT 240.
#define TFT_WIDTH  240
#define TFT_HEIGHT 320

// HSPI pins — unchanged from ILI9341 config
#define TFT_CS   15
#define TFT_DC    2
#define TFT_RST  -1
#define TFT_MOSI 13
#define TFT_MISO 12
#define TFT_SCK  14

#define TFT_BL   21
#define TFT_BACKLIGHT_ON HIGH

#define USE_HSPI_PORT

#define LOAD_GLCD
#define LOAD_FONT2
#define LOAD_FONT4
#define LOAD_FONT6
#define LOAD_FONT7
#define LOAD_FONT8
#define LOAD_GFXFF
#define SMOOTH_FONT

#define SPI_FREQUENCY      55000000
#define SPI_READ_FREQUENCY 20000000
