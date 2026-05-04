#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <TFT_eSPI.h>
#include <lvgl.h>
#include "font_digits_128.h"

#define TFT_BL_PIN  21
#define DISP_W      320
#define DISP_H      240

// ── ESPnow payload (must match transmitter) ────────────────────
struct __attribute__((packed)) EspNowPayload { uint32_t cpm; float hz; };

// ── Thread-safety: WiFi task → loop() ─────────────────────────
static portMUX_TYPE   mux         = portMUX_INITIALIZER_UNLOCKED;
static volatile bool  newPacket   = false;
static EspNowPayload  latestPkt;

// ── State machine ──────────────────────────────────────────────
enum RxState { LOST, RECEIVING };
static RxState        rxState      = LOST;
static unsigned long  lastPacketMs = 0;

// ── LVGL objects ───────────────────────────────────────────────
static lv_obj_t      *splash_scr, *main_scr;
static lv_obj_t      *rate_label, *unit_label, *icon_obj;
static lv_timer_t    *flash_timer  = nullptr;
static bool           iconFilled   = false;

// ── TFT + display buffer ───────────────────────────────────────
static TFT_eSPI       tft;
static lv_color_t     disp_buf[DISP_W * 20];

// ──────────────────────────────────────────────────────────────
// LVGL flush callback
// ──────────────────────────────────────────────────────────────
static void flush_cb(lv_display_t *disp, const lv_area_t *area, uint8_t *px_map) {
    uint32_t w = area->x2 - area->x1 + 1;
    uint32_t h = area->y2 - area->y1 + 1;
    tft.startWrite();
    tft.setAddrWindow(area->x1, area->y1, w, h);
    tft.pushColors((uint16_t *)px_map, w * h, true);  // true = swap bytes for ILI9341
    tft.endWrite();
    lv_display_flush_ready(disp);
}

static uint32_t tick_cb(void) { return millis(); }

// ──────────────────────────────────────────────────────────────
// ESPnow callback (runs in WiFi task — ISR-safe write only)
// ──────────────────────────────────────────────────────────────
static void onReceive(const esp_now_recv_info_t *info, const uint8_t *data, int len) {
    if (len != (int)sizeof(EspNowPayload)) return;
    portENTER_CRITICAL_ISR(&mux);
    memcpy((void *)&latestPkt, data, sizeof(EspNowPayload));
    newPacket = true;
    portEXIT_CRITICAL_ISR(&mux);
}

// ──────────────────────────────────────────────────────────────
// Icon style helpers (called only from loop / LVGL timers)
// ──────────────────────────────────────────────────────────────
static void iconSetFilled(void) {
    lv_obj_set_style_bg_opa(icon_obj, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_color(icon_obj, lv_color_hex(0x505050), 0);
    lv_obj_set_style_border_width(icon_obj, 0, 0);
}

static void iconSetHollow(void) {
    lv_obj_set_style_bg_opa(icon_obj, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(icon_obj, 2, 0);
    lv_obj_set_style_border_color(icon_obj, lv_color_hex(0x909090), 0);
    lv_obj_set_style_border_opa(icon_obj, LV_OPA_COVER, 0);
}

// ──────────────────────────────────────────────────────────────
// State transitions
// ──────────────────────────────────────────────────────────────
static void flashTimerCb(lv_timer_t *) {
    iconFilled = !iconFilled;
    if (iconFilled) iconSetFilled();
    else {
        lv_obj_set_style_bg_opa(icon_obj, LV_OPA_TRANSP, 0);
        lv_obj_set_style_border_width(icon_obj, 2, 0);
        lv_obj_set_style_border_color(icon_obj, lv_color_hex(0x505050), 0);
        lv_obj_set_style_border_opa(icon_obj, LV_OPA_COVER, 0);
    }
}

static void goLost(void) {
    rxState = LOST;
    if (flash_timer) { lv_timer_delete(flash_timer); flash_timer = nullptr; }
    iconSetHollow();
    lv_obj_set_style_text_color(rate_label, lv_color_hex(0x909090), 0);
    lv_obj_set_style_text_color(unit_label, lv_color_hex(0x909090), 0);
}

static void goReceiving(void) {
    rxState = RECEIVING;
    lv_obj_set_style_text_color(rate_label, lv_color_hex(0x000000), 0);
    lv_obj_set_style_text_color(unit_label, lv_color_hex(0x000000), 0);
    iconSetFilled();
    iconFilled = true;
    if (!flash_timer) flash_timer = lv_timer_create(flashTimerCb, 500, nullptr);
}

// ── 500 ms poll: drop to LOST if no packet for 3 s ─────────────
static void statePollCb(lv_timer_t *) {
    if (rxState == RECEIVING && (millis() - lastPacketMs) > 3000) goLost();
}

// ── Splash timer: switch to main screen after 20 s ─────────────
static void splashDoneCb(lv_timer_t *timer) {
    lv_timer_delete(timer);
    lv_screen_load(main_scr);
}

// ──────────────────────────────────────────────────────────────
// UI construction
// ──────────────────────────────────────────────────────────────
static void buildSplash(void) {
    splash_scr = lv_obj_create(nullptr);
    lv_obj_remove_flag(splash_scr, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_bg_color(splash_scr, lv_color_hex(0xFFFFFF), 0);
    lv_obj_set_style_bg_opa(splash_scr, LV_OPA_COVER, 0);

    lv_obj_t *lbl = lv_label_create(splash_scr);
    lv_label_set_text(lbl, "paddlestroke_espnow_rx");
    lv_obj_set_style_text_font(lbl, &lv_font_montserrat_24, 0);
    lv_obj_set_style_text_color(lbl, lv_color_hex(0x000000), 0);
    lv_obj_align(lbl, LV_ALIGN_CENTER, 0, 0);

    lv_timer_create(splashDoneCb, 20000, nullptr);
}

static void buildMain(void) {
    main_scr = lv_obj_create(nullptr);
    lv_obj_remove_flag(main_scr, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_bg_color(main_scr, lv_color_hex(0xFFFFFF), 0);
    lv_obj_set_style_bg_opa(main_scr, LV_OPA_COVER, 0);

    // Large rate number
    rate_label = lv_label_create(main_scr);
    lv_label_set_text(rate_label, "--");
    lv_obj_set_style_text_font(rate_label, &font_digits_128, 0);
    lv_obj_set_style_text_color(rate_label, lv_color_hex(0x909090), 0);
    lv_obj_align(rate_label, LV_ALIGN_CENTER, 0, -20);

    // CPM sub-label
    unit_label = lv_label_create(main_scr);
    lv_label_set_text(unit_label, "CPM");
    lv_obj_set_style_text_font(unit_label, &lv_font_montserrat_24, 0);
    lv_obj_set_style_text_color(unit_label, lv_color_hex(0x909090), 0);
    lv_obj_align(unit_label, LV_ALIGN_CENTER, 0, 90);

    // Signal icon — 20×20 filled circle, top-right corner
    icon_obj = lv_obj_create(main_scr);
    lv_obj_set_size(icon_obj, 20, 20);
    lv_obj_set_style_radius(icon_obj, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_pad_all(icon_obj, 0, 0);
    lv_obj_remove_flag(icon_obj, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(icon_obj, LV_ALIGN_TOP_RIGHT, -5, 5);
    iconSetHollow();
}

// ──────────────────────────────────────────────────────────────
// setup
// ──────────────────────────────────────────────────────────────
void setup() {
    Serial.begin(115200);

    // TFT
    tft.init();
    tft.invertDisplay(true);          // CYD2USB colour inversion fix
    tft.setRotation(1);               // landscape 320×240
    tft.fillScreen(TFT_WHITE);
    pinMode(TFT_BL_PIN, OUTPUT);
    digitalWrite(TFT_BL_PIN, HIGH);

    // LVGL
    lv_init();
    lv_tick_set_cb(tick_cb);
    lv_display_t *disp = lv_display_create(DISP_W, DISP_H);
    lv_display_set_flush_cb(disp, flush_cb);
    lv_display_set_buffers(disp, disp_buf, nullptr, sizeof(disp_buf),
                           LV_DISPLAY_RENDER_MODE_PARTIAL);

    buildSplash();
    buildMain();
    lv_screen_load(splash_scr);

    lv_timer_create(statePollCb, 500, nullptr);

    // WiFi + ESPnow
    WiFi.mode(WIFI_STA);
    esp_wifi_set_channel(1, WIFI_SECOND_CHAN_NONE);
    if (esp_now_init() != ESP_OK) {
        Serial.println("ESPnow init failed — halting");
        tft.fillScreen(TFT_BLACK);
        tft.setTextColor(TFT_RED, TFT_BLACK);
        tft.drawString("ESPnow FAILED", 60, 110, 4);
        while (true) delay(100);
    }
    esp_now_register_recv_cb(onReceive);
    Serial.println("paddlestroke_espnow_rx — ready");
}

// ──────────────────────────────────────────────────────────────
// loop
// ──────────────────────────────────────────────────────────────
void loop() {
    if (newPacket) {
        EspNowPayload pkt;
        portENTER_CRITICAL(&mux);
        pkt       = latestPkt;
        newPacket = false;
        portEXIT_CRITICAL(&mux);

        lastPacketMs = millis();

        if (lv_screen_active() == main_scr) {
            char rateBuf[8];
            snprintf(rateBuf, sizeof(rateBuf), "%lu", (unsigned long)pkt.cpm);
            lv_label_set_text(rate_label, rateBuf);
            if (rxState != RECEIVING) goReceiving();
        }
    }

    lv_timer_handler();
}
