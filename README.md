# 📒 My Vault — บันทึกส่วนตัว

## 🎮 Roblox--Library

คลังสคริปต์/โมดูล Roblox สำหรับเก็บและแชร์โค้ดที่นำกลับไปใช้ซ้ำได้ในหลายเกม
โดยเน้นโครงสร้างที่อ่านง่าย, แก้ไขต่อได้ง่าย, และแยกเป็นรายเกม/ระบบอย่างชัดเจน

**Project Status:** CLOSED (Maintenance Mode)  
ดูรายละเอียดที่ `PROJECT_STATUS.md`
สถานะปิดรอบนี้ไม่มี deferred ค้าง

### โครงสร้างโปรเจกต์
- `modules/` : เก็บโมดูลแยกตามชื่อเกมหรือระบบ
- `modules/umt/` : entrypoint แบบ modular ของ Ultimate Mining Tycoon (เริ่มใช้แล้ว)
- `RAVENHUB` : สคริปต์หลัก/ตัวรวมโค้ดที่ใช้ในโปรเจกต์
- `RavenHub_UMT_AutoSettings.json` : ตัวอย่าง/สำรองการตั้งค่า UMT (Ore ESP mappings, Auto Mine, ฯลฯ) — วางใน workspace ของ executor ใช้ชื่อนี้ให้ตรงกับ `writefile`/`readfile` ของโมดูล หรือวาง JSON แบบ `{ "kind":"UMTFullSettings", "data":{...} }` ในแท็บ Ore ESP → Import Full Settings
- `README.md` : เอกสารภาพรวมและแนวทางใช้งาน
- `SKILL.md` : แนวทางการทำงาน/มาตรฐานการเขียนร่วมกับ AI

### วิธีเพิ่มโมดูลใหม่
1. สร้างไฟล์ใหม่ในโฟลเดอร์ `modules/` โดยตั้งชื่อให้สื่อความหมายของเกม/ระบบ
2. ใส่ส่วนหัวคอมเมนต์บอกชื่อโมดูล, เวอร์ชัน, และคำอธิบายสั้นๆ
3. แยกค่าคอนฟิกที่แก้บ่อยไว้ด้านบนไฟล์เพื่อง่ายต่อการปรับแต่ง
4. ทดสอบการทำงานพื้นฐานก่อนบันทึกเข้า repository

### Ultimate Mining Tycoon (Current)
- ฟีเจอร์หลักที่ใช้งานจริง: `Auto Mine`, `Auto Sell`, `Ore ESP`, utility แบบ remote prompt
- ฟีเจอร์ที่ถูกถอดออกจากโมดูลนี้: `Teleport/Waypoint TP/Tween`
- Hub จะโหลดผ่าน entrypoint `modules/umt/main.lua` แล้ว bridge ไปยัง legacy module เพื่อค่อยๆ ย้ายเป็นหลายไฟล์โดยไม่ทำให้ของเดิมพัง

### Settings Schema
- ไฟล์ `RavenHub_UMT_AutoSettings.json` ใช้ `settingsVersion` สำหรับ migration
- โครงสร้างแบบ wrapper `{ "kind":"UMTFullSettings", "data":{...} }` ยังรองรับ
- เมื่อเจอเวอร์ชันเก่า สคริปต์จะอัปเกรดค่าในหน่วยความจำและบันทึกกลับด้วย schema ล่าสุดอัตโนมัติ

### Smoke Test Checklist (หลังแก้โค้ดทุกครั้ง)
- เปิด `RAVENHUB` แล้วให้ UMT โหลดสำเร็จผ่าน `modules/umt/main.lua` โดยไม่มี error notification
- เปิด/ปิด `Ore ESP`, ปรับระยะ, เปลี่ยนฟิลเตอร์ และกด refresh แล้ว UI/visual ไม่ค้าง
- เปิด `Auto Mine` 2-3 นาที ตรวจว่า status มีการเปลี่ยนจริงและไม่ขึ้น queue exhausted ถี่ผิดปกติ
- ทดสอบ `Sell Ore` แบบ remote ว่าขายได้จากระยะไกล และค่าที่เซฟ (toggle/range/filter) โหลดกลับรอบถัดไป
- กด `Destroy Hub` แล้ว ensure cleanup สำเร็จ ไม่มี ESP/Highlight ค้างในโลกเกม

### Known Issues (Current)
- เมื่อเกมอัปเดตโครงสร้าง ore ใหม่ อาจต้อง import mapping หรือเรียนรู้ชื่อใหม่เพิ่ม
- บาง executor ที่บล็อก `writefile/readfile` จะใช้ได้แต่ไม่สามารถ persistent settings ข้ามรัน
- ถ้า raw GitHub cache หน่วง อาจโหลด helper เวอร์ชันเก่าในช่วงสั้นๆ (มี query version ช่วยลดปัญหา)

### มาตรฐานแนะนำสำหรับ Roblox Lua
- หลีกเลี่ยงการใช้ global variables โดยไม่จำเป็น
- แยกฟังก์ชันตามหน้าที่ ลดการทำงานซ้ำ
- ตั้งชื่อตัวแปร/ฟังก์ชันให้สื่อความหมายชัดเจน
- เขียนคอมเมนต์เฉพาะจุดที่ logic ซับซ้อน
- ตรวจสอบ input และสถานะเกมก่อน execute logic สำคัญ

### Change Log (Roblox--Library/Ultimate Mining Tycoon)
- ปิดโปรเจกเป็นสถานะ `CLOSED (Maintenance Mode)` และเพิ่มไฟล์ `PROJECT_STATUS.md` เพื่อกำหนดขอบเขตงานปิดรอบนี้อย่างชัดเจน
- เก็บก้อน `Auto Mine runtime utility` เพิ่ม: helper รองรับ `isMadCommIdAllowed`, `markMadCommRemoteInvalid`, `ensureRemoteClientDrain`, `nextDrillPacketNonce` และไฟล์หลักเรียกผ่าน helper พร้อม fallback ครบ
- ปิดก้อน `Auto Mine remote resolver` เพิ่ม: helper `modules/umt/systems/auto_mine.lua` รองรับ `resolveActivateRemote` และ `pickMineActivateRemoteAlternateDiscovered` พร้อมผูก counter กลับเข้า runtime เดิม
- ขยาย `Auto Mine` helper เพิ่ม: ย้าย utility `MadComm/grid packet` ไป `modules/umt/systems/auto_mine.lua` (collect entries, resolve tool id, grid candidates) แล้วให้ไฟล์หลักเรียกผ่าน helper พร้อม fallback
- ขยับการแยก `Ore ESP runtime` เพิ่ม: ย้าย logic scan/watch โฟลเดอร์แร่ไป helper (`scanAll`, `bindFolder` ใน `modules/umt/systems/esp_runtime.lua`) และให้ไฟล์หลักเรียกผ่าน helper พร้อม fallback เดิม
- เริ่มแยก `Auto Mine` helper: เพิ่ม `modules/umt/systems/auto_mine.lua` (utility `randomRange` และ `hasNearbyPlayers`) และผูกเรียกจากไฟล์หลักแบบ fallback
- แยก `Ore ESP runtime helpers` เพิ่ม: สร้าง `modules/umt/systems/esp_runtime.lua` (clearAll / setVisualVisibility / syncVisualStyle) และให้ไฟล์หลักเรียกผ่าน helper เพื่อลดภาระโค้ดใน loop หลัก
- เพิ่ม utility ฝั่ง `modules/umt/systems/esp.lua`: `countActiveVisuals()` และ `applyAdaptiveCadence()` แล้วผูกให้ไฟล์หลักเรียกผ่าน helper (มี fallback local) เพื่อลดโค้ดซ้ำใน loop อัปเดต ESP
- เพิ่มเอกสารปฏิบัติการ: `Smoke Test Checklist` และ `Known Issues` ใน README เพื่อให้ตรวจ regression และดูข้อจำกัดปัจจุบันได้เร็ว
- เริ่ม Phase 3 ของการแยก `Ore ESP`: เพิ่ม `modules/umt/systems/esp.lua` สำหรับรวม state เริ่มต้น + color/category mapping ของ ESP และให้ไฟล์หลักโหลดผ่าน helper (มี fallback local เดิม)
- เริ่ม Phase 2 ของการแยกไฟล์: เพิ่มโมดูล `modules/umt/core/settings.lua` และให้ `modules/Ultimate Mining Tycoon` โหลด helper นี้เพื่อจัดการ defaults/unwrap/migration ของ settings แบบแยก concern (มี fallback local เดิมหากโหลด helper ไม่สำเร็จ)
- เพิ่มโครงสร้างโหลดแบบ modular สำหรับ UMT: `RAVENHUB` ชี้ไป `modules/umt/main.lua` และใช้ `legacy_bridge.lua` เพื่อรักษา behavior เดิมระหว่างย้ายโค้ดเป็นหลายไฟล์
- เพิ่ม `settingsVersion` ใน `RavenHub_UMT_AutoSettings.json` และรองรับ migration/fallback (รวมการอ่าน payload แบบ wrapper `UMTFullSettings`)
- อัปเดตคำอธิบาย UMT ใน `RAVENHUB` ให้ตรงฟีเจอร์จริง (ตัด Teleport ออกจากคำบรรยาย)
- ปรับลดอาการแลคของ `Ore ESP`: เพิ่ม adaptive throttle ตามจำนวนก้อนที่ติด visual (ลดความถี่ update/meta refresh เมื่อก้อนเยอะ), ข้ามการสร้าง ESP ให้ก้อนที่ไกลเกินระยะ + padding, และกันสแกน `GetDescendants` ตอน ESP ปิด
- เพิ่ม `auto-sync` ฝั่ง `Auto Mine`: อ่าน `MadCommId` แบบ deep จาก tool (attributes/value objects/descendants) และปรับ resolver ดาเมจให้สแกนค่าที่เกี่ยวกับ `damage/mining/power/strength` ก่อน fallback ตามชื่อ pickaxe เพื่อลดเคสแพ็กเก็ตไม่ตรงค่าจริงของอุปกรณ์
- harden เพิ่ม `Auto Mine` จากผล Remote Spy: เมื่อเปิด `Force Mining Damage` จะ bypass ฟิลเตอร์ `RequiredStrength` ฝั่งสคริปต์ (ให้เซิร์ฟเวอร์ตัดสินจริง) และเพิ่ม `grid candidates` สำรอง (`attribute / world-int / world/4`) พร้อมสลับลองอัตโนมัติเมื่อ HP ไม่ขยับ
- เพิ่มตัวเลือก `Force Mining Damage` และ `Force MadCommId` ใน `Auto Mine` (0 = auto detect) เพื่อแก้เคสที่แพ็กเก็ตจริงไม่ตรงค่าที่สคริปต์คำนวณ; ใช้ได้ตรงกับข้อมูล Remote Spy เช่น `98` + `1312`
- แก้ `Auto Mine` เคสยิงขุดไม่เข้าเพราะ pickaxe ยังไม่ equip จริง: บังคับรอให้ pickaxe อยู่ใน `Character` ก่อนยิง `Activate` (เพิ่มสถานะ `equipping pickaxe` / `waiting pickaxe equip`) ลดอาการวนกลับมาขุดก้อนเดิมแล้ว HP ไม่ลง
- ปรับ `Auto Mine` สำหรับแร่ชั้นลึก/HP สูง: ขยาย `hit/time limits` ตาม `expectedHits`, เพิ่ม `no-progress grace window` (ต้องยิงครบขั้นต่ำ + ใช้เวลาขั้นต่ำก่อนสลับเป้า) เพื่อลดอาการหลุดเป้ากลางทางเมื่อ pickaxe ขุดช้า
- เพิ่ม `RavenHub_UMT_AutoSettings.json` (export แบบ flat สำหรับ `readfile`) รวม `oreNameByColorSignature` / signature maps / ignore list ตามโปรไฟล์ UMT; เพิ่มชื่อแร่ `EXPLOSIVES` ใน `knownOreNames` + สี/หมวด ESP
- `Ultimate Mining Tycoon`: รวม `espRescanIfEnabled` / `espSyncAfterMappingUpdate` ลดโค้ดซ้ำระหว่าง Import Full / Reset mapping / ฟิลเตอร์ ESP / Refresh
- เริ่มเพิ่มเอกสารภาพรวมของโปรเจกต์ใน `README.md`
- แก้ `modules/Ultimate Mining Tycoon` ให้ Ore ESP ติดกับแร่ที่เป็นทั้ง `BasePart` และ `Model`
- เพิ่มปุ่ม `Destroy Menu (Reload Script)` ใน `modules/Ultimate Mining Tycoon` เพื่อปิดสคริปต์และรันใหม่ได้ทันที
- แก้ `modules/My_knife_farm` ไม่ให้ fallback ไป `Plots.Plot_1` แบบตายตัว
- ปรับ `RAVENHUB` ระบบคัดโหลดโมดูลให้รองรับ `placeIds/gameIds` และเพิ่มตัวตรวจจับแมพสำรองของ UMT
- แก้ `modules/Ultimate Mining Tycoon` ไม่ให้เรียก destroy อัตโนมัติตอนเริ่มโหลด (แก้ปัญหาเมนูปิดเองทันที)
- แก้ `RAVENHUB` ให้ retry โหลดโมดูลที่ใช้ detector นานสูงสุด 30 วินาที และกันโหลดซ้ำด้วย `loadedScripts`
- ปรับระบบ cleanup: ใช้ `Destroy Hub` ใน `RAVENHUB` เป็นตัวกลางเรียก cleanup ของโมดูล (รวม `Ultimate Mining Tycoon`) แทนการ destroy UI เองในโมดูล
- บันทึกเหตุการณ์: อาการเมนูปิดเองยังเกิดซ้ำ เพราะ `modules/Ultimate Mining Tycoon` โหลด Rayfield ใหม่ซ้อนกับ Hub
- แก้ล่าสุด: ส่ง `hubRayfield` จาก `RAVENHUB` เข้าโมดูล และให้ UMT ใช้ instance เดิมแทนการ `loadstring` Rayfield ใหม่
- ปรับระบบอ่านชื่อแร่ใน `modules/Ultimate Mining Tycoon`: อ่านจาก attributes/descendants + normalize ชื่อ (ตัด `Block/Mesh`, แยก CamelCase) และ cache ชื่อเพื่อลดชื่อผิดแบบ `Unknown/GemBlockMesh`
- ปรับกลับเป็นแบบเดิมตามคำสั่ง: ชื่อแร่ใช้แหล่งข้อมูลหลักเดิม และกรณีไม่ทราบชื่อให้แสดง `OreMesh` แทน `Unknown`
- แก้ fallback ชื่อแร่เพิ่มเติม: กรณีชื่อ generic เป็น `SurfaceAppearance` ให้แสดง `OreMesh` แทน
- ปรับ `modules/Ultimate Mining Tycoon` ให้สี ESP แยกตามหมวดหมู่แร่ (Common Metal / Rare Metal / Radioactive / Precious / Gemstone / Mythic / Unknown)
- ปรับ `Auto Mine` ให้คัดแร่ด้วยชื่อจากระบบ ESP (`getOreName`) และใช้ `Ore Ignore List` จากชื่อเดียวกันแทนการเช็ค `MineId`
- แก้เพิ่มจากผลทดสอบ: map สีให้ชื่อ runtime ในเกม (`OreMesh`, `CubicBlockMetal`, `ShaleMetalBlock`, `GemBlockMesh`) และปรับ `Unknown` ให้เป็นสีส้มเพื่อแยกชัด
- แก้เพิ่ม `Auto Mine` ให้สแกนทั้ง `PlacedOre` และ `SpawnedBlocks` พร้อมคัดเฉพาะก้อนที่มีข้อมูลขุดได้จริง (`MineId/OreId/ChunkPosition/GridPosition`)
- แก้บัค `Auto Mine` ยังเงียบ: ปรับเงื่อนไข equip pickaxe จาก backpack ให้ถูกต้อง และแก้การหา `Activate` remote ให้รองรับ `MadCommId` ทุกชนิด (ค้นผ่าน `FindFirstChild(tostring(MadCommId))`)
- อ้างอิง packet ที่จับได้: เพิ่ม fallback `MadCommEvents["1726"].Activate` ใน `Auto Mine` และเพิ่มการหา `GridPosition/ChunkPosition` จาก descendants เพื่อให้ยิงขุดตรงกับ remote ของแมพ
- แก้เพิ่ม `Auto Mine` รอบล่าสุด: ไม่บังคับ dependency กับ tool ก่อนยิงขุด (หากหา remote ได้จะยิงทันที) และเพิ่มสถานะ debug ใน `OreLabel` เช่น `mining ...`, `no target in range`, `Activate remote missing`
- แก้เพิ่ม `Auto Mine` จากสถานะ `no target in range`: ผ่อนเงื่อนไขเลือกเป้าให้ยึดก้อนที่มี `BasePart` จริง (ไม่บังคับ attribute), รองรับ target ที่เป็น Folder/Nested object และให้ resolve remote `1726` ได้แม้หา tool ไม่เจอ
- ปรับ `Auto Mine` ให้ไม่หลุด target โดยเพิ่มระบบล็อกเป้า (target lock) และแสดงสถานะ `mining <ore> (locked)` พร้อมเพิ่มโหมด `Tween to Ore (Experimental)` และตัวปรับ `Tween Speed` เพื่อวิ่งเข้าหาแร่ก่อนขุด
- เพิ่มเครื่องมือ `Ore Name Debug / Mapping` ใน `modules/Ultimate Mining Tycoon`: จับ ore ที่กำลังเล็ง, แสดง `MineId/OreId + ชื่อที่ resolve ได้`, และบันทึกแมพ `id -> ชื่อจริง` แบบ manual เพื่อให้ Ore ESP แสดงชื่อจริงได้แม่นขึ้นในแมพที่ใช้ชื่อ runtime
- แก้ error โหลดโมดูล `Ultimate Mining Tycoon` (`attempt to call a nil value`): ทำ forward declaration ให้ `getOreRenderPart` เพื่อให้ `resolveOreName` เรียกใช้งานได้ถูกต้องตามลำดับ scope
- แก้ซ้ำกรณี `attempt to call a nil value` ที่ `resolveOreName`: เพิ่ม safe fallback สำหรับหา `renderPart` เมื่อ helper function ยังไม่พร้อม เพื่อกันสคริปต์หยุดระหว่างสร้างแท็บ Farm
- harden ระบบชื่อแร่/ดีบักเพิ่ม: ตรวจชนิดข้อมูลให้เป็น `Instance` ก่อนเรียกเมธอด (`IsA`, `FindFirstChildWhichIsA`) และเปลี่ยน icon แจ้งเตือนใน Ore Debug เป็น asset id ที่ Rayfield รองรับ เพื่อลด error ระหว่างโหลด UI
- เพิ่ม guard ให้ `Auto Mine/Tween` หยุดชั่วคราวตอนผู้เล่นนั่งยานพาหนะ (`Humanoid.SeatPart`) และแสดงสถานะ `paused (in vehicle)` เพื่อลดการชนกับระบบรถของเกม (`InnoVehicles`)
- เพิ่มการเดาชื่อแร่เชิงลึกใน Ore ESP: สแกน descendant hints/ชื่อ node แบบ normalize + keyword match กับรายชื่อแร่ที่รู้จัก และเพิ่ม fallback mapping `runtime name -> ชื่อจริง` (ใช้ได้แม้ `MineId/OreId` เป็น `N/A`)
- เพิ่มระบบบันทึกการตั้งค่าอัตโนมัติของ `modules/Ultimate Mining Tycoon` ลงไฟล์ `RavenHub_UMT_AutoSettings.json` (Auto Mine/Auto Sell/Tween/Range/Delay/Ore Ignore/Ore Mapping) พร้อมโหลดคืนอัตโนมัติเมื่อรันครั้งถัดไป
- ปรับระบบ mapping ชื่อแร่ให้แม่นขึ้น: เพิ่ม `ore signature` (ClassName/Name/Material/Color/Size/MeshId/TextureID) เพื่อ map `signature -> ชื่อจริง` แทนการเหมารวมด้วย runtime name (`OreMesh`) เพียงอย่างเดียว
- แก้ความเสถียรของแท็บ `Farm`: sanitize ค่า `Ore Ignore List` ที่โหลดจากไฟล์ก่อนผูกเข้ากับ Rayfield dropdown และ fallback options แบบปลอดภัย เพื่อลดโอกาส UI พังกลางโหลดจนเห็นแค่บางส่วน
- แก้บัคลำดับ scope ของฟังก์ชัน (`makeOreSignature` เรียก `isInstance` ก่อนประกาศ): ย้าย `isInstance` ให้ประกาศก่อนใช้งาน เพื่อลด error `attempt to call a nil value` ตอนโหลดโมดูล
- harden เพิ่มที่ `makeOreSignature`: ครอบการคำนวณด้วย `pcall` + safe resolve ของ `getOreRenderPart` เพื่อตัดกรณี `attempt to call a nil value` ที่เกิดซ้ำระหว่างโหลดแท็บ Farm
- ปรับความแม่นชื่อแร่ ESP เพิ่มเติม: รองรับชื่อ `Sliver` (ตามข้อมูลในเกม), ปรับ matcher ให้เช็คแบบคำเต็ม (word boundary) และจำกัด descendant hint เฉพาะ `StringValue` ที่เกี่ยวกับ ore/resource เพื่อลดการเดาผิดเป็น `Tin/Iron` จากชื่อย่อยที่ไม่เกี่ยวข้อง
- เพิ่มระบบ `auto ore inference + auto learning`: ดึง candidate ชื่อแร่จาก attributes/value objects/บริบท parent แบบให้คะแนนความมั่นใจ และบันทึก `signature/id -> name` อัตโนมัติเมื่อ confidence สูง เพื่อลดการ map มือเป็นหลัก
- เพิ่ม hardening สำหรับแท็บ Farm/ESP: ครอบงานอัปเดต `RenderStepped` ด้วย `pcall` กันเคส object แร่ผิดรูปพา UI ล้มทั้งแท็บ
- ปรับระบบจำชื่อแร่ให้ติดมากขึ้น: เพิ่ม `coarse signature` (Material/Color/MeshId/TextureID) เป็นชั้น fallback ของ memory และบันทึกลงไฟล์ settings พร้อมสถานะ `load/save` ใน UI เพื่อเช็กได้ว่าเซฟจริงหรือไม่
- ลดการเดาชื่อผิดของ ESP: จำกัดแหล่ง inference ให้เชื่อเฉพาะ metadata ที่มีคีย์บอกความเป็นแร่ (ore/mine/resource/...) และตัดข้อมูลจาก UI descendants ออก พร้อมเพิ่ม threshold ความมั่นใจและไม่ auto-learn ถ้าไม่มี `OreId/MineId`
- แก้เคสชื่อแร่หลุดเดี่ยว (outlier) เช่น `Plutonium` โผล่ในกลุ่ม `Titanium`: เพิ่มระบบ `neighbor consensus` (majority vote จากก้อนใกล้เคียงที่มีแมพเชื่อถือได้) เพื่อ auto-correct ชื่อที่แมพผิดในระดับ signature/coarse
- แก้ `Auto Mine` อาการค้างเป้าซ้ำ (ขุดไม่ต่อเนื่อง): เพิ่มระบบตรวจ `stuck target` จากการล็อกก้อนเดิมหลายรอบติด และบังคับ `re-target` อัตโนมัติเมื่อเกิน threshold เพื่อลดการต้องปิด/เปิด Auto Mine เอง
- แก้ error `AutoMine/OreESP` (`attempt to call a nil value` ที่ `getMappedOreNameOnly`): ทำ forward declaration ให้ `getOreIdentifierDeep` (แก้ลำดับ scope ของ Lua) และใส่ guard เช็กชนิดฟังก์ชันก่อนเรียกในเส้นทาง resolve/map
- harden ซ้ำจุด crash `getMappedOreNameOnly`: ครอบ lookup ด้วย `pcall` และเปลี่ยน parser ใน `makeOreSignatureCoarse` จาก `string.split` เป็น `string.gmatch` เพื่อกัน environment ที่ไม่มี helper แล้วเด้ง `attempt to call a nil value`
- ปรับแก้ตามข้อมูล Dex จริงของ ore (`CrystallineMetalOre`): เพิ่ม memory ชั้น `color signature` (Class/Material/Color/MeshId) และลดการพึ่ง runtime mapping generic เพื่อลดชื่อแร่มั่ว
- แก้ `Auto Mine` ค้างก้อนเดิมเพิ่ม: ใส่ระบบ `temporary target blacklist` เมื่อ detect stuck แล้ว re-target ไปก้อนอื่นอัตโนมัติ ลดการวนขุดก้อนเดิมซ้ำ
- ปรับระบบแยกชื่อแร่เป็นโหมด `strict color-signature`: ใช้ rule จาก Dex (`ClassName+Material+Color+MeshId`) เป็นแหล่งจริงก่อนทุกอย่าง, ปิดการ auto-learn เดาในโหมดนี้, และ fallback เป็น `Unknown` เมื่อไม่ตรง rule เพื่อหยุดการเดามั่ว
- แก้ Rayfield callback error จากการอัปเดตข้อความสถานะใน Label (`Title is not a valid member of Frame "Label"`): ครอบการ `Set` ของ UI label ด้วย `pcall` ผ่าน helper `safeSetUiText` เพื่อกันเมนูล่มกลางใช้งาน
- ปรับลำดับ priority ของ mapping ในโหมด strict เพิ่ม: ให้ `static color-signature` และ `color-signature` มาก่อน signature/coarse เสมอ และตอน map manual จะบันทึกสีเป็นหลักใน strict mode เพื่อลดการทับค่าผิดจาก signature เก่า
- ปรับความปลอดภัยของ rule เริ่มต้น: ลบ preset ชื่อแร่แบบ hardcoded ที่ยังไม่ยืนยันออก (เริ่ม static table ว่าง) และเพิ่มปุ่ม `Reset Learned Ore Maps` ในแท็บ Farm เพื่อเคลียร์ mapping ที่เรียนรู้ผิดได้ทันที
- เพิ่มชั้นยืนยันก่อนรีเซ็ต mapping: ปุ่ม `Reset Learned Ore Maps` ต้องกดซ้ำภายใน 6 วินาทีจึงจะรีเซ็ตจริง (กันการเผลอกดจากตำแหน่งปุ่มที่อยู่ใกล้กัน)
- ปรับ UX การยืนยันรีเซ็ตเป็น popup กลางจอใน UI (`Confirm Reset / Cancel`) แทนการกดซ้ำเวลา เพื่อให้เห็นชัดและลดการกดผิด
- เพิ่มตัวจำแนกชื่อแร่จาก `Color` โดยตรงในโหมด strict (`direct color classifier`): เทียบระยะสีจริงของก้อนแร่กับ palette แร่ และใช้ threshold + confidence margin เพื่อลดการแมพผิดจากข้อมูลอื่นที่ปนใน descendants/UI
- ปรับ `Ore ESP` ให้ใช้สีไฮไลท์จาก `part.Color` ของก้อนแร่โดยตรง (รวมสีข้อความป้าย) แทนการไล่สีตามความหายาก
- แก้ปัญหาสี ESP เพี้ยนจนต้องกด Refresh: อัปเดต `Ore ESP` ให้ sync `Adornee/Color/Size/TextColor` ตาม `renderPart` แบบเรียลไทม์ใน `RenderStepped` เพื่อให้สีตรงทันทีโดยไม่ต้อง re-scan
- บันทึกข้อผิดพลาดและแก้ไข: การ “เดาชื่อแร่จาก palette สีที่ hardcode” ทำให้ชื่อเพี้ยนได้ (เช่น `Aluminium` ถูกเดาเป็น `Vanadium`) จึงปรับ `direct color classifier` ให้ใช้เฉพาะสีจาก mapping ที่ยืนยันแล้ว (`oreNameByColorSignature`) เท่านั้น และถ้าไม่มั่นใจให้เป็น `Unknown` แทนการเดามั่ว
- ปรับ `Ore ESP` เป็นโหมดไม่เดา (strict): ปิด neighbor-consensus สำหรับ strict mode และให้ ESP แสดงชื่อเฉพาะจาก mapping ที่ยืนยันแล้ว (`id/static-color/color-signature`) เท่านั้น; ไม่ตรงให้ขึ้น `Unknown` เพื่อกันทับซ้อน/เดามั่ว
- ปรับสีไฮไลท์ `Ore ESP` ให้ตรง `part.Color` มากขึ้น: ตัดการผสมสีโดยตั้ง `OutlineColor = FillColor` และตั้ง `FillTransparency = 0` เพื่อไม่ให้ blend กับฉากหลัง/แสง
- แก้สีไฮไลท์ยังเพี้ยน (โดยเฉพาะ `Neon`): เปลี่ยน visual ของ ESP จาก `Highlight` เป็น `BoxHandleAdornment` (ใช้ `Color3` ตรง + คุม transparency เอง) เพื่อให้สีตรงกับ `part.Color` มากที่สุด
- แก้ `Ore ESP` สีเขียว/ผิดสีทั้งที่ Properties เป็นสีอื่น: ปรับ `getOreRenderPart()` ให้เลือก `MeshPart`/ชิ้นที่เห็นจริงก่อน (และ fallback เป็น `BasePart` ที่ใหญ่สุด) เพื่ออ่าน `part.Color` จากชิ้นที่ถูกต้อง ไม่หลุดไปอ่านจาก part ลูกที่สีคนละตัว
- แชร์ mapping ชื่อแร่: ใช้ **Export / Import Full Settings** (รวม `sharedOreNameByColorSignature` + map อื่นๆ); ลบปุ่ม Export/Import Shared Color Map แยกเพื่อลดซ้ำ
- เปลี่ยนระบบวาร์ปหลักทั้งหมดใน `modules/Ultimate Mining Tycoon` ให้ใช้ Tween (`tweenHumanoidRootPart`) แทนการเซ็ต `CFrame` ตรง เพื่อให้การย้ายตำแหน่งลื่นและสม่ำเสมอทั้ง Teleport/Waypoint/Shop/Sell/Vehicle
- แก้ `Ore Ignore List` ให้แสดงรายการแร่ครบทั้งระบบ (จาก `knownOreNames` + mapping ที่เรียนรู้) ไม่ยึดเฉพาะแร่ที่กำลังสปอนใน `PlacedOre` เพื่อเลือก ignore ได้ครบตั้งแต่เริ่ม
- เพิ่มโหมด `Safe Profile` ใน `modules/Ultimate Mining Tycoon`: ปรับ Auto Mine/Auto Sell ให้สุ่มจังหวะมากขึ้น, ใส่ cooldown, ชะลอ tween, และ pause อัตโนมัติเมื่อมีผู้เล่นอยู่ใกล้ เพื่อลดพฤติกรรมที่ดูผิดธรรมชาติ
- เพิ่มตัวปรับในแท็บ `Teleport` สำหรับความเร็ววาร์ป: `Teleport Tween Speed` และ `Teleport Max Duration` พร้อมบันทึกค่าใน settings เพื่อให้ชะลอการวาร์ปหลักได้ตามต้องการ
- รวมระบบการเคลื่อนที่ทั้งหมดให้ใช้ tween helper เดียว (`tweenHumanoidRootPart`) ครอบคลุมทั้ง Teleport/Waypoint/Sell/Shop/Vehicle และ Auto Mine tween เพื่อให้พฤติกรรมการเคลื่อนที่สม่ำเสมอทั้งไฟล์
- ปรับ `Auto Mine` ให้รีเป้าอัตโนมัติเมื่อขุดแร่ก้อนเดิมครบ 15 ครั้งแล้วยังไม่แตก/ยังไม่ได้ของ โดยบล็อกก้อนนั้นชั่วคราวแล้วสลับไปหาแร่อื่น
- แยกเมนู `Ore ESP` ออกจากแท็บ `Farm` ไปแท็บใหม่ `Ore ESP` โดยย้าย controls/debug/mapping/filter ทั้งหมดไปหมวดเฉพาะ เพื่อจัดโครงสร้างเมนูให้ใช้งานง่ายขึ้น
- ปรับระบบขายแร่ให้ขายได้จากทุกที่ (ไม่ต้อง tween/tp): รวม logic เป็น helper เดียวและให้ `Sell Ore`, `Auto Sell`, และ `Sell Ore Key` ยิง `ProximityPrompt` ระยะไกลโดยตรง
- เพิ่มตัวเลือกวิธีขายแร่ 2 โหมด (`Remote (No TP)` / `Tween to Unloader (Legacy)`) และให้ทั้งปุ่มขาย, Auto Sell, และคีย์ลัดใช้โหมดเดียวกัน พร้อมบันทึกค่าลง settings
- แก้ `Auto Mine` ลดโอกาสขึ้น `Remote event invocation queue exhausted`: เพิ่ม hard rate-limit ตอนยิง `Activate`, ครอบ `FireServer` ด้วย `pcall`, และใส่ backoff อัตโนมัติเมื่อ remote ตอบสนองไม่ทัน
- แก้ซ้ำเคส `Remote event invocation queue exhausted` ของ `MadCommEvents.*.Activate`: ผูกตัวรับ `OnClientEvent` แบบ drain เงียบให้ remote ขุดที่ใช้งาน เพื่อไม่ให้คิว event ฝั่ง client สะสมจนล้น
- ปรับ `Remote Sell` ให้เช็กผลขายจริงจากจำนวนแร่ก่อน/หลังกด prompt; ถ้าโดนเซิร์ฟเวอร์บล็อกระยะจะ fallback ไป `Tween to Unloader (Legacy)` อัตโนมัติ เพื่อให้ขายได้ต่อเนื่อง
- ปรับโหมด anti-shadowban: ปิดการขายแบบ `Tween` ในระบบฟาร์ม (บังคับ `Remote (No TP / No Tween)`), เอา fallback tween ออก และล็อก `Tween to Ore` ให้ไม่ทำงานพร้อมแจ้งเตือนเมื่อเปิด
- ลบระบบเคลื่อนที่ `TP/Tween` ออกจาก `modules/Ultimate Mining Tycoon` ทั้งแท็บ Teleport/Waypoint และปรับ Vehicle/Shop ให้ยิง `ProximityPrompt` ระยะไกลแทน
- ปรับ `Ore ESP` เป็นโหมด `Highlight` (ลด fill/คง outline) เพื่อลดการบังข้อความป้าย และทำให้สีมองชัดขึ้น
- แก้ `Ore Ignore List` ใน `Auto Mine`: เปลี่ยนให้คัดแร่จากชื่อเส้นทางเดียวกับ ESP (`getOreNameForEsp`) และ normalize รายชื่อ ignore ใน callback เพื่อกันชื่อไม่ตรงแล้วยังถูกขุด
- ปรับ `Auto Mine` ให้ลดการสแปมขุด: ใช้ค่าแรงขุดตาม Pickaxe (`Damage/MiningPower` ฯลฯ) แทนค่าคงที่, หน่วงจังหวะแบบ adaptive ตามดาเมจ, และเพิ่ม backoff เมื่อ durability/HP ของก้อนไม่ขยับ
- ปรับ `Auto Mine` ให้หลุดจากก้อนที่ขุดนานผิดปกติเร็วขึ้น: เพิ่มเงื่อนไขสลับเป้าเมื่อ `no progress` หลายรอบ, จำกัดเวลา lock ต่อก้อนตาม `HP/Damage`, และลด hit-limit แบบ dynamic ต่อก้อน
- แก้ `Auto Mine` หาเป้าไม่เจอในบางแมพ: ปรับ resolver ให้รองรับ ore ที่ถูกจัดเป็น nested folder ใต้ `PlacedOre/SpawnedBlocks` (`IsDescendantOf`) และปรับสแกนเป้าให้ไล่ลึกแบบ dedupe
- แก้ซ้ำ `Auto Mine` ยังไม่เจอ ore หลัง rollback: ผ่อนเงื่อนไข `mineable` ให้เช็ค `GridPosition/ChunkPosition` แบบ deep (descendants) ก่อนคัดทิ้ง เพราะบางก้อนเก็บ attribute ไว้ที่ชิ้นย่อยไม่ใช่ node บนสุด
- ปรับ `Auto Mine` ให้หาเป้าแบบ `Ore ESP` เป็นหลัก: เลือก target จาก `ESP.activeVisuals` (ก้อนที่ ESP เห็นอยู่แล้ว) แล้วค่อย fallback ไปสแกน `PlacedOre/SpawnedBlocks` และเลิกบังคับ `mineable` เพื่อกันกรองทิ้งผิด
- Rollback เพิ่ม: กลับไปใช้วิธีหาเป้าแบบแรก (สแกน `PlacedOre/SpawnedBlocks:GetChildren()` แล้วเลือกก้อนที่ใกล้สุดในระยะ) ไม่พึ่ง `Ore ESP` ในการเลือกเป้า
- ปรับ `Ore ESP` ให้ติดครบขึ้นในแมพที่แร่ถูกซ้อนในโฟลเดอร์: สแกน descendants ของ `PlacedOre/SpawnedBlocks` สำหรับการสร้างไฮไลท์ และขยายระบบบันทึก settings ให้ครอบคลุมเพิ่ม (`WalkSpeed`, `Infinite Jump`, `Sell Ore Key`, `Ore ESP` เปิด/ระยะ/ฟิลเตอร์)
- แก้ `Ore ESP` ซ้อนทับหนาแน่น: บังคับ `1 ESP ต่อ 1 renderPart` (กัน label/box ซ้อนหลายชั้นบนก้อนเดียว) และยกตำแหน่งป้ายชื่อขึ้นเพื่อลดการบัง
- Optimization ประสิทธิภาพ: throttle อัปเดต ESP (`RenderStepped`) เป็นช่วง, cache metadata ชื่อ/สีแร่พร้อม refresh เป็นรอบ, อัปเดตข้อความระยะเฉพาะเมื่อค่าเปลี่ยน, และ cache reference โฟลเดอร์แร่ใน Auto Mine เพื่อลด `FindFirstChild` ซ้ำ
- ปรับ `Auto Mine` ให้ใช้ทั้งราคาและ `RequiredStrength` จากตาราง `oreReferenceFromList` ในโค้ด (sync กับ repo `Ore list`) เท่านั้น — ไม่อ่าน economy จากอินสแตนซ์แร่ในเกม
- แก้ `Auto Mine` แร่ HP สูงขุดไม่รู้จบ: ค่า `hardHitLimit` / `hitSwitchLimit` / `targetTimeLimit` เดิมต่ำเกิน (เช่น 8 ครั้ง / 6 วินาที / สูงสุด 15 รอบ) ทำให้สลับเป้าก่อนแร่แตก — ปรับให้สเกลตาม `expectedHits` และ delay จริง
- `modules/Ultimate Mining Tycoon` ไม่ `loadstring` Rayfield ซ้ำแล้ว — บังคับใช้ `scriptInfo.hubRayfield` จาก `RAVENHUB` เท่านั้น (โหลดนอก Hub จะ warn แล้ว return)
- แก้ `Auto Mine` อาการขุดสะดุด/บางทีไม่ขุด: ไม่นับ `staleProgressHits` ตอนยังรอ `minReadyAt` (เรทลิมิต) เพราะ HP ไม่ขยับเหมือน “ค้าง” ทำให้โดนสลับเป้า `no progress` ผิดๆ
- แก้เคสแร่ “วนเต็ม/ไม่ได้ของ” ที่เซิร์ฟไม่รับดาเมจ: ตรวจ HP กระโดดขึ้นหลังยิงแล้ว → สถานะ `ore HP reset (server) — skip block` + บล็อกเป้าชั่วคราว
- `Auto Mine` แสดงสัญญาณบนก้อนแร่ที่กำลังขุด: `Highlight` + ป้าย `⛏ AUTO MINE` (ล้างเมื่อปิด Auto / เปลี่ยนเป้า / pause / Destroy Hub)
- harden runtime error/log spam: ครอบ `Rayfield.Notify` ด้วย `pcall` (safe notify) กันเคส UI template เปลี่ยนแล้วเด้ง `Template is not a valid member of Frame "Notifications"` และเพิ่มตัว drain ให้ remote ชื่อ `RegisterInstanceChanges` เพื่อลด `Remote event invocation queue exhausted`
- เพิ่มระบบแชร์คอนฟิกทั้งก้อนใน `modules/Ultimate Mining Tycoon`: รองรับ `Export/Import Full Settings` (JSON copy/paste) รวมค่าฟาร์ม/ESP/mapping ชื่อแร่ทั้งหมด เพื่อย้ายโปรไฟล์ไปอัปเดตชื่อแร่ในสคริปต์หรือแชร์ให้เครื่องอื่นได้ทันที

> แก้ไขไฟล์นี้ได้โดยตรง หรือบอก Claude ให้เพิ่ม/แก้ไขแทน

---

## 👤 ข้อมูลส่วนตัว
- ฉันชื่อ "นายท่าน"

---

## 📋 กรอบปฏิบัติ
- "ทุกครั้งที่เขียนฟังก์ชันเกี่ยวกับเงิน (Economy system) ให้เพิ่มฟังก์ชัน LogTransaction() เสมอเพื่อกันการโกง"
- การอัปโหลดไฟล์ README.md หรือ API Documentation ของระบบที่คุณกำลังพัฒนา เพื่อให้ AI อ้างอิงเวลาเขียนโค้ดต่อยอด
- สำหรับโปรเจกต์ FiveM นี้ ให้ใช้ ESX Framework เป็นหลักเสมอ" หรือ "ห้ามใช้ global variables ในโค้ด Lua เด็ดขาด
- ให้บันทึกทุกครั้ง ที่ทำการแก้ไขบัคต่างๆ หรือ ทำอะไรไป

---

## 💡 ความรู้ / สูตร
- ## Role & Persona You are a Senior Tech Lead and System Architect with deep expertise in full-stack engineering, game engine scripting (Lua for FiveM/Roblox), and low-level system programming (C++, Rust). You are meticulous, security-conscious, and prioritize clean, scalable, and memory-efficient code.  ## Standard Operating Procedure (Workflow) When tasked with any coding or technical request, strictly follow this workflow:  1. **Context & Requirement Analysis:** - Before writing code, briefly summarize your understanding of the user's goal.     - Identify potential constraints (e.g., performance limits in FiveM, resource handling in Roblox).  2. **Architectural Design:** - Propose an efficient structure or logic flow before diving into implementation.     - If security is involved, explicitly adopt a "Defensive Security" mindset: analyze the design for potential vulnerabilities (e.g., injection, race conditions) and propose hardening strategies.  3. **Implementation:** - Write high-quality, documented, and idiomatic code.     - Use language-specific best practices (e.g., O-notation optimization, modular structure).    - If the code is for game scripts, prioritize server/client synchronization and performance.  4. **Review & Optimization:** - Self-correct: Check for common bugs and logic flaws.    - Refactor: Suggest one optimization or alternative approach to improve the code.  ## Interaction Guidelines - Be direct, professional, and efficient.  - Avoid lecturing; assume the user is an experienced developer. - If a request touches on security-sensitive topics (e.g., exploit analysis), frame the response within an educational, research, or defensive (Blue Team) context. Focus on mitigation, vulnerability assessment, and robust system design. - Always be ready to discuss GitHub project structures, CI/CD, and professional deployment standards.

---

## 🔧 โปรเจกต์
- https://github.com/valrinxx/Fivem-Server-Real4Life

---

## 📝 บันทึกอื่นๆ
<!-- ว่างอยู่ -->