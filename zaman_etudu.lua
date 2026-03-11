-- ==========================================================
--  ZAMAN ETÜDÜ / TIME STUDY - VLC Lua Eklentisi
--  Schneider Electric Manisa - Zaman Analizi Aracı
-- ==========================================================
--  Kullanım:
--    1) Bu dosyayı kopyala:
--       %APPDATA%\vlc\lua\extensions\zaman_etudu.lua
--    2) VLC'yi aç/yeniden başlat
--    3) Menü: Görünüm (View) → Zaman Etüdü / Time Study
--    4) Videoyu oynat, istediğin anda "Zamanı Kaydet" butonuna bas
--    5) Zaman otomatik panoya kopyalanır (Ctrl+V ile Excel'e yapıştır)
--    6) Bitince "CSV'ye Aktar" ile tüm listeyi Excel'e aktar
-- ==========================================================

function descriptor()
    return {
        title = "Zaman Etüdü / Time Study",
        version = "1.0",
        author = "SE Manisa",
        shortdesc = "Video zaman analizi aracı",
        description = "Videodan zaman damgası yakala, panoya kopyala, CSV'ye aktar.",
        capabilities = {}
    }
end

-- ============ DEĞİŞKENLER ============
local timestamps = {}
local dlg = nil
local list_widget = nil
local status_label = nil
local note_input = nil

-- ============ YARDIMCI FONKSİYONLAR ============

-- Mikrosaniyeyi okunabilir formata çevir
local function format_time(microseconds)
    local total_sec = microseconds / 1000000
    local h = math.floor(total_sec / 3600)
    local m = math.floor((total_sec % 3600) / 60)
    local s = math.floor(total_sec % 60)
    local ms = math.floor((total_sec * 1000) % 1000)
    return string.format("%02d:%02d:%02d.%03d", h, m, s, ms), total_sec
end

-- Windows panoya kopyala
local function copy_to_clipboard(text)
    -- clip.exe Windows'ta yerleşik, doğrudan çalışır
    local cmd = 'echo|set /p="' .. text .. '"| clip'
    os.execute(cmd)
end

-- Mevcut oynatma zamanını al
local function get_current_time()
    local input = vlc.object.input()
    if not input then
        return nil, nil
    end
    local time_us = vlc.var.get(input, "time")
    return format_time(time_us)
end

-- Durum mesajı güncelle
local function set_status(msg)
    if status_label then
        status_label:set_text(msg)
        dlg:update()
    end
end

-- ============ ANA FONKSİYONLAR ============

-- Zamanı yakala ve panoya kopyala
function capture_time()
    local formatted, seconds = get_current_time()
    if not formatted then
        set_status("⚠ Video açık değil!")
        return
    end

    -- Not alanından açıklama al
    local note = ""
    if note_input then
        note = note_input:get_text() or ""
    end

    local step = #timestamps + 1
    table.insert(timestamps, {
        step = step,
        time = formatted,
        seconds = seconds,
        note = note
    })

    -- Listeye ekle
    local display = "Adım " .. step .. "  |  " .. formatted
    if note ~= "" then
        display = display .. "  |  " .. note
    end
    list_widget:add_value(display, step)

    -- Panoya kopyala (Excel'e yapıştırmak için TAB ile)
    -- Format: Adım[TAB]Zaman[TAB]Saniye[TAB]Not
    local clipboard_text = formatted
    copy_to_clipboard(clipboard_text)

    set_status("✓ Adım " .. step .. ": " .. formatted .. " (panoya kopyalandı)")

    -- Not alanını temizle (bir sonraki adım için)
    if note_input then
        note_input:set_text("")
    end
end

-- Son kaydı panoya kopyala
function copy_last()
    if #timestamps == 0 then
        set_status("⚠ Henüz kayıt yok!")
        return
    end
    local last = timestamps[#timestamps]
    copy_to_clipboard(last.time)
    set_status("✓ Panoya kopyalandı: " .. last.time)
end

-- Tüm listeyi TAB-separated olarak panoya kopyala (Excel'e toplu yapıştır)
function copy_all_to_clipboard()
    if #timestamps == 0 then
        set_status("⚠ Henüz kayıt yok!")
        return
    end

    -- Başlık satırı + veri satırları (TAB separated, Excel dostu)
    local lines = {}
    table.insert(lines, "Adım\tZaman\tSaniye\tNot")
    for _, t in ipairs(timestamps) do
        table.insert(lines, t.step .. "\t" .. t.time .. "\t"
            .. string.format("%.3f", t.seconds) .. "\t" .. (t.note or ""))
    end

    -- Geçici dosyaya yaz, sonra clip'e aktar
    local tmpfile = os.getenv("TEMP") .. "\\zaman_etudu_tmp.txt"
    local f = io.open(tmpfile, "w")
    if f then
        f:write(table.concat(lines, "\n"))
        f:close()
        os.execute('clip < "' .. tmpfile .. '"')
        set_status("✓ " .. #timestamps .. " kayıt panoya kopyalandı! Excel'de Ctrl+V yap.")
    end
end

-- CSV dosyasına aktar
function export_csv()
    if #timestamps == 0 then
        set_status("⚠ Dışa aktarılacak kayıt yok!")
        return
    end

    -- Masaüstüne kaydet
    local desktop = os.getenv("USERPROFILE") .. "\\Desktop\\"
    local filename = "zaman_etudu_" .. os.date("%Y%m%d_%H%M%S") .. ".csv"
    local path = desktop .. filename

    local file = io.open(path, "w")
    if not file then
        -- Masaüstü olmazsa VLC dizinine yaz
        path = vlc.config.userdatadir() .. "\\" .. filename
        file = io.open(path, "w")
    end

    if file then
        -- BOM + CSV header (Türkçe Excel için UTF-8 BOM ve noktalı virgül)
        file:write("\xEF\xBB\xBF")
        file:write("Adım;Zaman;Saniye;Not\n")
        for _, t in ipairs(timestamps) do
            file:write(t.step .. ";"
                .. t.time .. ";"
                .. string.format("%.3f", t.seconds) .. ";"
                .. (t.note or "") .. "\n")
        end
        file:close()
        set_status("✓ Kaydedildi: " .. filename .. " (Masaüstü)")
    else
        set_status("⚠ Dosya yazılamadı!")
    end
end

-- Son kaydı sil
function undo_last()
    if #timestamps == 0 then
        set_status("⚠ Silinecek kayıt yok!")
        return
    end
    local removed = table.remove(timestamps)
    -- Listeyi yeniden oluştur
    list_widget:clear()
    for _, t in ipairs(timestamps) do
        local display = "Adım " .. t.step .. "  |  " .. t.time
        if t.note and t.note ~= "" then
            display = display .. "  |  " .. t.note
        end
        list_widget:add_value(display, t.step)
    end
    set_status("✓ Adım " .. removed.step .. " silindi.")
end

-- Tüm kayıtları temizle
function clear_all()
    timestamps = {}
    list_widget:clear()
    set_status("✓ Tüm kayıtlar temizlendi.")
end

-- ============ DİYALOG (ARAYÜZ) ============

function activate()
    dlg = vlc.dialog("⏱ Zaman Etüdü / Time Study")

    -- Satır 1: Ana butonlar
    dlg:add_button("⏱ ZAMANI KAYDET", capture_time, 1, 1, 2, 1)
    dlg:add_button("↩ Geri Al", undo_last, 3, 1, 1, 1)

    -- Satır 2: Not alanı
    dlg:add_label("Not:", 1, 2, 1, 1)
    note_input = dlg:add_text_input("", 2, 2, 2, 1)

    -- Satır 3: Kayıt listesi
    list_widget = dlg:add_list(1, 3, 3, 1)

    -- Satır 4: Dışa aktarma butonları
    dlg:add_button("📋 Tümünü Kopyala", copy_all_to_clipboard, 1, 4, 1, 1)
    dlg:add_button("💾 CSV Aktar", export_csv, 2, 4, 1, 1)
    dlg:add_button("🗑 Temizle", clear_all, 3, 4, 1, 1)

    -- Satır 5: Durum çubuğu
    status_label = dlg:add_label("Hazır. Videoyu oynatıp 'Zamanı Kaydet' butonuna basın.", 1, 5, 3, 1)

    dlg:show()
end

function deactivate()
    if dlg then
        dlg:delete()
        dlg = nil
    end
end

function close()
    deactivate()
end
