# Ziro - Asistente Financiero Personal 🚀

[![Flutter](https://img.shields.io/badge/Flutter-3.0+-blue.svg)](https://flutter.dev)
[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Dart](https://img.shields.io/badge/Dart-3.0+-blue.svg)](https://dart.dev)

Ziro es una aplicación móvil de finanzas personales desarrollada en **Flutter** que permite gestionar ingresos, gastos y ahorros con tasas de cambio oficiales del **Banco Central de Venezuela (BCV)** actualizadas automáticamente.

---

## 📱 Capturas de pantalla

<div align="center">
  <table>
    <tr>
      <td align="center">
        <img src="https://raw.githubusercontent.com/Jerougez/Ziro-app/main/screenshots/home.png" width="250" alt="Pantalla de inicio">
        <br><b>Pantalla de inicio</b>
      </td>
      <td align="center">
        <img src="https://raw.githubusercontent.com/Jerougez/Ziro-app/main/screenshots/stats.png" width="250" alt="Estadísticas mensuales">
        <br><b>Estadísticas mensuales</b>
      </td>
      <td align="center">
        <img src="https://raw.githubusercontent.com/Jerougez/Ziro-app/main/screenshots/entry.png" width="250" alt="Nuevo registro">
        <br><b>Nuevo registro</b>
      </td>
    </tr>
    <tr>
      <td align="center">
        <img src="https://raw.githubusercontent.com/Jerougez/Ziro-app/main/screenshots/goals.png" width="250" alt="Metas de ahorro">
        <br><b>Metas de ahorro</b>
      </td>
      <td align="center">
        <img src="https://raw.githubusercontent.com/Jerougez/Ziro-app/main/screenshots/emergency.png" width="250" alt="Fondo de emergencia">
        <br><b>Fondo de emergencia</b>
      </td>
      <td align="center">
        <img src="https://raw.githubusercontent.com/Jerougez/Ziro-app/main/screenshots/settings.png" width="250" alt="Pantalla de ajustes">
        <br><b>Pantalla de ajustes</b>
      </td>
    </tr>
  </table>
</div>

---

## ✨ Características Principales

### 🔐 Seguridad
- **Bloqueo biométrico** con huella digital o reconocimiento facial
- Almacenamiento local seguro con Shared Preferences

### 💰 Gestión de Saldos
- Saldo en **Bolívares (Bs)**
- Saldo en **Dólares (USD)**
- Conversión automática a **Euros (EUR)** con tasa BCV

### 📊 Registro de Movimientos
- **Ingresos** (+) - Cuando recibes dinero
- **Gastos** (-) - Cuando pagas algo
- **Ahorros** - Para cumplir metas
- **Categorías**: Comida, Transporte, Servicios, Ocio, Salud, Educación, Emergencia

### 🎯 Metas de Ahorro
- Crear metas con nombre y foto
- Seguimiento de progreso en porcentaje (%)
- Mensajes motivadores al retirar ahorros

### 🛡️ Fondo de Emergencia
- Agregar desde saldo o dinero externo
- Retirar solo en situaciones de EMERGENCIA REAL

### 📈 Estadísticas Mensuales
- Ingresos totales del mes
- Gastos totales del mes
- Ahorro acumulado
- Desglose por categorías con porcentajes
- Alertas si gastas más de lo que ingresas

### ⚡ Actualización Automática de Tasas
- **4 APIs diferentes** para garantizar disponibilidad
- Tasas oficiales del **BCV** actualizadas diariamente
- Fallback automático si no hay internet

### 📤 Exportación de Datos (GDPR)
- Exportar todos los datos a JSON
- Compartir por cualquier medio
- Cumplimiento de normativas de privacidad

---

## 🛠️ Tecnologías Utilizadas

| Tecnología | Uso |
|------------|-----|
| **Flutter** | Framework principal (UI multiplataforma) |
| **Dart** | Lenguaje de programación |
| **Shared Preferences** | Almacenamiento local de datos |
| **Local Authentication** | Biometría (huella/rostro) |
| **HTTP / REST APIs** | Consumo de APIs del BCV |
| **Provider / SetState** | Manejo de estado |
| **Intl** | Formateo de fechas y números |
| **Image Picker** | Selección de imágenes para metas |
| **Share Plus** | Exportación de datos (GDPR) |
| **URL Launcher** | Política de privacidad |

---

## 🔄 Fuentes de Tasas BCV

Ziro obtiene las tasas de cambio desde **4 fuentes diferentes** en orden de prioridad:

| Prioridad | API | URL |
|-----------|-----|-----|
| 1️⃣ | PydolarVenezuela | `pydolarvenezuela-api.onrender.com/api/v1/bcv` |
| 2️⃣ | BCV API OnRender | `bcv-api.onrender.com/api/rates/all` |
| 3️⃣ | BCV API Latest | `bcv-api.onrender.com/api/rates/latest` |
| 4️⃣ | Fluentax API | `api.fluentax.com/exchange-rates/banks/central-bank-of-venezuela/latest` |

Si una API falla, automáticamente usa la siguiente. ¡Nunca te quedarás sin tasas!

---

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