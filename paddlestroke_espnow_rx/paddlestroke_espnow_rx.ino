#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>

struct __attribute__((packed)) EspNowPayload {
    uint32_t cpm;
    float    hz;
};

static void onReceive(const esp_now_recv_info_t* info, const uint8_t* data, int len) {
    if (len != sizeof(EspNowPayload)) return;
    EspNowPayload payload;
    memcpy(&payload, data, sizeof(payload));
    Serial.print("CYCLE_RATE: ");
    Serial.print(payload.cpm);
    Serial.print(" CPM  (");
    Serial.print(payload.hz, 2);
    Serial.println(" Hz)");
}

void setup() {
    Serial.begin(115200);
    Serial.println("ESPnow RX — ready");

    WiFi.mode(WIFI_STA);
    esp_wifi_set_channel(1, WIFI_SECOND_CHAN_NONE);

    if (esp_now_init() != ESP_OK) {
        Serial.println("ESPnow init failed — halting");
        while (true) delay(100);
    }

    esp_now_register_recv_cb(onReceive);
    Serial.println("Listening on channel 1...");
}

void loop() {}
