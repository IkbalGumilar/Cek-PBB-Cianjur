"""Password-based encryption shared by the Python .dkhp package generators."""

import getpass
import hashlib
import os

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

MAGIC = b"DKH2"
SALT_LENGTH = 16
NONCE_LENGTH = 12
ITERATIONS = 600_000


def prompt_password() -> str:
    password = getpass.getpass("Kata sandi backup (minimal 12 karakter): ")
    confirmation = getpass.getpass("Ulangi kata sandi backup: ")
    if len(password) < 12:
        raise ValueError("Kata sandi harus terdiri dari minimal 12 karakter.")
    if password != confirmation:
        raise ValueError("Kata sandi tidak cocok.")
    return password


def encrypt_zip(zip_bytes: bytes, password: str) -> bytes:
    if len(password) < 12:
        raise ValueError("Kata sandi harus terdiri dari minimal 12 karakter.")
    salt = os.urandom(SALT_LENGTH)
    nonce = os.urandom(NONCE_LENGTH)
    header = MAGIC + salt + nonce
    key = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt, ITERATIONS, dklen=32
    )
    return header + AESGCM(key).encrypt(nonce, zip_bytes, header)
