# Bash Scripts Collection

Hey there! Welcome to my collection of handy bash scripts! 

I've put together these little helpers after running into the same DevOps challenges over and over again. Sisyphus is jealous.

## 🎯 What's This All About?

This repository is filled with practical, no-nonsense bash scripts that tackle real-world problems. Each one is crafted to be simple, readable and focused.

## 🛠️ The Scripts

### ⚓ Kubernetes Management

#### 📦 `backup-k8s-secrets-configmaps.sh`
*Because losing secrets is never fun!*

Ever had that sinking feeling when you realize you should have backed up your cluster's secrets and configmaps? Yeah, me too. That's why this script exists!

**What it does:**
- Creates a nicely organized, timestamped backup directory (no more guessing when you made that backup!)
- Goes through ALL your namespaces
- Exports secrets and configmaps as clean YAML files
- Keeps everything organized by namespace (your future self will love this)

**What you'll need:**
- `kubectl` set up and logged into your cluster (you probably already have this!)
- Permission to peek at secrets and configmaps (hopefully you do! 😊)

**How to use it:**
```bash
./backup-k8s-secrets-configmaps.sh
```

**What you'll get:**
A beautifully organized backup folder that looks like this:
```
k8s-backup-YYYYMMDDHHMMSS/
├── namespace1/
│   ├── secrets/
│   │   ├── secret1.yaml
│   │   └── secret2.yaml
│   └── configmaps/
│       ├── configmap1.yaml
│       └── configmap2.yaml
└── namespace2/
    └── ...
```

#### 📜 `get-cert-secrets-expiration-dates.sh`
*No more surprise certificate expirations!*

We've all been there: that moment when you realize a certificate expired and broke something. This script helps you stay ahead of those "oh no" moments!

**What it does:**
- Hunts down all TLS certificate secrets across your entire cluster
- Decodes the certificate data (no need to do mental gymnastics with base64!)
- Shows you when certificates were issued AND when they expire
- Presents everything in human-readable format (because who likes epoch timestamps?)

**What you'll need:**
- `kubectl` ready to go
- `openssl` and `jq` on your system (most systems have these already)
- Permission to read secrets (crossing fingers for you!)

**How to use it:**
```bash
./get-cert-secrets-expiration-dates.sh
```

**Sample output:**
*(This is what peace of mind looks like)*
```
NAMESPACE    NAME               ISSUED_DATE              EXPIRATION_DATE          EXPIRE_YEAR
kube-system  my-tls-secret     Jan  1 00:00:00 2024 GMT  Jan  1 00:00:00 2025 GMT  2025
default      app-cert          Mar 15 12:00:00 2024 GMT  Mar 15 12:00:00 2025 GMT  2025
```

### ☁️ Azure Key Vault Management

#### 🔐 `backup-transfer-akv.sh`
*Moving secrets around like a pro!*

Need to migrate Key Vault contents or create a backup? This script has got your back!

**What it does:**
- Copies ALL secrets from source to target Key Vault
- Migrates all keys while preserving their properties
- Transfers certificates with all their metadata intact
- Handles cross-subscription moves
- Keeps all the important key operations and properties

**What you'll need:**
- Azure CLI (`az`) installed and logged in
- Proper permissions on both Key Vaults (hopefully your admin likes you! 😄)
- `jq` for JSON parsing (lightweight and super handy)

**Setting it up:**
Just edit these variables at the top of the script with your info:
```bash
SOURCE_AKV_NAME="your-source-keyvault"
SOURCE_RESOURCE_GROUP="source-rg"
TARGET_AKV_NAME="your-target-keyvault"
TARGET_RESOURCE_GROUP="target-rg"
SOURCE_SUBSCRIPTION_ID="source-sub-id"
TARGET_SUBSCRIPTION_ID="target-sub-id"
```

**How to use it:**
```bash
./backup-transfer-akv.sh
```

## 🚀 Getting Started

Ready to dive in? Here's how to get rolling:

1. **Grab what you need** - Clone this repo or just download the scripts that caught your eye
2. **Make them executable** - `chmod +x *.sh` (gotta tell your system these are scripts!)
3. **Check the requirements** - Each script lists what it needs (don't worry, it's usually stuff you already have)
4. **Customize the settings** - Some scripts need you to fill in your specific details
5. **Test drive safely** - Always try things out in a safe environment first (trust me on this one!)

## 🤝 Contributing

Found a bug? Got a cool enhancement idea? Want to add your own script to the collection? Want to chat? Feel free to reach out!

I'd love to hear from you! These scripts are meant to be community-friendly starting points. Got a better way to do something? Spotted an edge case I missed? See a typo that's bugging you? Let me know! 

## ⚠️ Just a Heads Up

These scripts come from real-world experience, but every environment is different! Please:

- **Review the code first** - I encourage you to peek under the hood and understand what's happening
- **Test in a safe space** - Your dev environment will thank you for being cautious
- **Follow your org's rules** - Every company has different security and operational guidelines
- **Use at your own discretion** - These work great for me, but your mileage may vary!

## 🔮 What's Coming Next?

This collection is growing all the time! I'm always running into new challenges that need scriptable solutions. Here's what's on my wishlist:

- 🐳 **Docker/container management goodies** - Because containers are everywhere now
- 🔄 **CI/CD pipeline helpers** - Automating the automation! 
- 🏗️ **Infrastructure automation scripts** - Making terraform and other tools even easier
- 📊 **Monitoring and alerting utilities** - Because staying on top of things matters
- 🎯 **Whatever DevOps curveball comes up next** - The fun never stops in this field!

Got an idea for a script that would make your life easier? Let me know! These scripts exist because we all face similar challenges, yours might be the next one that helps everyone.

---

*🎩 Simple scripts for everyday DevOps magic*

**Happy scripting!** ✨