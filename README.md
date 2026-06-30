# Ziro - Asistente Financiero Personal 🚀

Ziro es una aplicación móvil de finanzas personales desarrollada en Flutter que permite gestionar ingresos, gastos y ahorros con tasas de cambio oficiales del Banco Central de Venezuela (BCV).

## ✨ Características

- 💰 Gestión de saldos en Bs, USD y EUR
- 📊 Estadísticas mensuales por categorías
- 🎯 Metas de ahorro con seguimiento de progreso
- 🛡️ Fondo de emergencia
- 🔐 Autenticación biométrica (huella/rostro)
- 📤 Exportación de datos (GDPR)
- ⚡ Actualización automática de tasas BCV desde múltiples APIs

## 🛠️ Tecnologías

- **Flutter** - Framework multiplataforma
- **Dart** - Lenguaje de programación
- **Shared Preferences** - Almacenamiento local
- **Local Authentication** - Biometría
- **HTTP / REST APIs** - Consumo de APIs del BCV
- **Provider / SetState** - Manejo de estado

## 🚀 Instalación

```bash
# Clonar el repositorio
git clone https://github.com/Jerougez/Ziro-app.git

# Entrar al directorio
cd Ziro-app

# Instalar dependencias
flutter pub get

# Ejecutar la app
flutter run