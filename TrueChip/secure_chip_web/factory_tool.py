import psycopg2
import time

# ==============================================================================
# DÁN EXTERNAL DATABASE URL CỦA BẠN VÀO ĐÂY (Nằm trong dấu ngoặc kép)
# ==============================================================================
EXTERNAL_DB_URL = "postgresql://truechip_db_user:3LLZ3QENjkr8QIW81rF4ya6HWpyu5beN@dpg-d9bf33ucjfls7387oi00-a.oregon-postgres.render.com/truechip_db"

def add_chip():
    print("=== CÔNG CỤ NHẬP KHO TRUECHIP TẠI NHÀ MÁY ===")
    
    uid_hex = input("Nhập UID của chip (32 ký tự Hex): ").strip().upper()
    secret_key_hex = input("Nhập Secret Key (32 ký tự Hex): ").strip().upper()
    product = input("Nhập tên sản phẩm (VD: TrueChip V2): ").strip()
    
    if len(uid_hex) != 32 or len(secret_key_hex) != 32:
        print("\n[LỖI] UID và Secret Key phải dài chính xác 32 ký tự (16-byte).")
        return

    print("\nĐang kết nối lên Đám mây...")
    try:
        conn = psycopg2.connect(EXTERNAL_DB_URL)
        cur = conn.cursor()
        
        # 1. TỰ ĐỘNG XÂY NHÀ KHO NẾU CHƯA CÓ
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS chips (
                uid VARCHAR(32) PRIMARY KEY,
                secret_key VARCHAR(32) NOT NULL,
                product VARCHAR(255) NOT NULL,
                manufacturer VARCHAR(255) NOT NULL,
                pack_date VARCHAR(255) NOT NULL,
                active INTEGER NOT NULL DEFAULT 1,
                created_at BIGINT NOT NULL
            )
            """
        )
        
        # 2. ĐẨY DỮ LIỆU VÀO
        cur.execute(
            """
            INSERT INTO chips(uid, secret_key, product, manufacturer, pack_date, active, created_at)
            VALUES (%s, %s, %s, %s, %s, 1, %s)
            ON CONFLICT(uid) DO UPDATE SET 
                secret_key=EXCLUDED.secret_key,
                product=EXCLUDED.product
            """,
            (uid_hex, secret_key_hex, product, "Huy Le Corp", time.strftime("%d/%m/%Y"), int(time.time()))
        )
        
        conn.commit()
        cur.close()
        conn.close()
        print(f"[THÀNH CÔNG] Đã ghi danh chip {uid_hex[:8]}... vào Cloud Database!")
        
    except Exception as e:
        print(f"\n[LỖI KẾT NỐI]: {e}")

if __name__ == '__main__':
    add_chip()
