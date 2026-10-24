#!/usr/bin/env python3
"""
Pembuat Paket Berkas .dkhp Terenkripsi (Format Khusus Aplikasi Cek PBB Cianjur).

Cara pakai:
    python3 tool/make_dkhp_package.py --data data.csv --photos ./foto --output Paket_Dusun3.dkhp
"""

import argparse
import io
import os
import sys
import zipfile
from dkhp_crypto import encrypt_zip, prompt_password


def build_dkhp(
    data_csv_path: str,
    photos_dir: str | None,
    output_path: str,
    unencrypted: bool = False,
    password: str | None = None,
) -> None:
    if not os.path.exists(data_csv_path):
        raise FileNotFoundError(f"File data CSV tidak ditemukan: {data_csv_path}")

    if not output_path.endswith('.dkhp') and not output_path.endswith('.zip'):
        output_path += '.dkhp'

    print(f"[*] Menyiapkan paket DHKP: {output_path}...")
    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, 'w', compression=zipfile.ZIP_DEFLATED) as zf:
        # Masukkan file data utama
        zf.write(data_csv_path, arcname="data.csv")
        print("  [+] data.csv disertakan.")

        # Masukkan file-file foto jika ada
        if photos_dir and os.path.exists(photos_dir):
            count = 0
            for root, _, files in os.walk(photos_dir):
                for f in files:
                    ext = os.path.splitext(f)[1].lower()
                    if ext in ('.jpg', '.jpeg', '.png', '.webp'):
                        full_path = os.path.join(root, f)
                        arc_name = f"foto/{f}"
                        zf.write(full_path, arcname=arc_name)
                        count += 1
            print(f"  [+] {count} file foto disertakan dalam folder foto/.")

    zip_bytes = zip_buffer.getvalue()

    if unencrypted:
        print("  [!] Mode tidak terenkripsi dipilih.")
        final_bytes = zip_bytes
    else:
        if password is None:
            raise ValueError("Kata sandi backup diperlukan untuk enkripsi.")
        print("  [*] Mengenkripsi paket dengan AES-256-GCM...")
        final_bytes = encrypt_zip(zip_bytes, password)

    with open(output_path, 'wb') as f:
        f.write(final_bytes)

    print(f"[✓] Selesai! Berkas siap diunggah ke aplikasi: {output_path} ({len(final_bytes)} bytes)")

def main():
    parser = argparse.ArgumentParser(description="Buat paket berkas .dkhp terenkripsi untuk aplikasi Cek PBB Cianjur")
    parser.add_argument("--data", required=True, help="Path ke file data.csv")
    parser.add_argument("--photos", default=None, help="Folder berisi file foto JPG/PNG (opsional)")
    parser.add_argument("--output", default="paket_dhkp.dkhp", help="Nama file output .dkhp")
    parser.add_argument("--unencrypted", action="store_true", help="Keluarkan berkas tanpa enkripsi (plain zip)")
    parser.add_argument(
        "--password-stdin",
        action="store_true",
        help="Baca kata sandi dari stdin untuk pemanggilan non-interaktif.",
    )
    args = parser.parse_args()

    password = None
    if not args.unencrypted:
        password = (
            sys.stdin.readline().rstrip("\r\n")
            if args.password_stdin
            else prompt_password()
        )
        if len(password) < 12:
            parser.error("Kata sandi harus terdiri dari minimal 12 karakter.")
    build_dkhp(
        args.data,
        args.photos,
        args.output,
        unencrypted=args.unencrypted,
        password=password,
    )

if __name__ == "__main__":
    main()
