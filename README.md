# 📒 My Vault — บันทึกส่วนตัว

## 🎮 Roblox--Library

คลังสคริปต์/โมดูล Roblox สำหรับเก็บและแชร์โค้ดที่นำกลับไปใช้ซ้ำได้ในหลายเกม
โดยเน้นโครงสร้างที่อ่านง่าย, แก้ไขต่อได้ง่าย, และแยกเป็นรายเกม/ระบบอย่างชัดเจน

### โครงสร้างโปรเจกต์
- `modules/` : เก็บโมดูลแยกตามชื่อเกมหรือระบบ
- `RAVENHUB` : สคริปต์หลัก/ตัวรวมโค้ดที่ใช้ในโปรเจกต์
- `README.md` : เอกสารภาพรวมและแนวทางใช้งาน
- `SKILL.md` : แนวทางการทำงาน/มาตรฐานการเขียนร่วมกับ AI

### วิธีเพิ่มโมดูลใหม่
1. สร้างไฟล์ใหม่ในโฟลเดอร์ `modules/` โดยตั้งชื่อให้สื่อความหมายของเกม/ระบบ
2. ใส่ส่วนหัวคอมเมนต์บอกชื่อโมดูล, เวอร์ชัน, และคำอธิบายสั้นๆ
3. แยกค่าคอนฟิกที่แก้บ่อยไว้ด้านบนไฟล์เพื่อง่ายต่อการปรับแต่ง
4. ทดสอบการทำงานพื้นฐานก่อนบันทึกเข้า repository

### มาตรฐานแนะนำสำหรับ Roblox Lua
- หลีกเลี่ยงการใช้ global variables โดยไม่จำเป็น
- แยกฟังก์ชันตามหน้าที่ ลดการทำงานซ้ำ
- ตั้งชื่อตัวแปร/ฟังก์ชันให้สื่อความหมายชัดเจน
- เขียนคอมเมนต์เฉพาะจุดที่ logic ซับซ้อน
- ตรวจสอบ input และสถานะเกมก่อน execute logic สำคัญ

### Change Log (Roblox--Library/Ultimate Mining Tycoon)
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