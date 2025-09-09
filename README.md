Perfeito 🐸👌 — segue o **README.md** revisado, com um **título mais profissional** e sem repetir a parte da licença:

````markdown
# nano-ntp — Minimal SNTP Client in Assembly

<p align="center">
  <img src="src/logo.png" alt="nano-ntp logo" width="200"/>
</p>

**nano-ntp** is a minimal SNTP client written in pure x86_64 assembly.  
The binary is less than 1 KB and synchronizes Linux system time using Google and Cloudflare NTP servers.

---

## 📥 Clone & Build

```bash
git clone https://github.com/victormeloasm/nntp.git
cd nntp
fasm nntp.asm
````

This will generate the `nntp` binary in the current directory.

---

## ⚙️ Usage

Make the binary executable:

```bash
chmod +x ./nntp
```

Synchronize the system clock:

```bash
sudo ./nntp
```

Alternatively, grant the capability to run without `sudo`:

```bash
sudo setcap cap_sys_time=+ep ./nntp
./nntp
```

Check the new system time:

```bash
date
```

---

## 📂 Project Structure

```
nntp/
├── nntp.asm       # source code (x86_64 assembly)
├── src/logo.png   # project logo
└── README.md
```

```

👉 Quer que eu também prepare um **systemd unit file** pronto (`nntp.service`) pra incluir no repositório, assim quem instalar pode rodar o sync automaticamente no boot?
```
