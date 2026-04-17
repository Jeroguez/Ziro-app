plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.jeroguez.ziro"
    compileSdk = 36 // Cambiado a 36 para estabilidad
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.jeroguez.ziro"
        minSdk = flutter.minSdkVersion // Te recomiendo fijarlo en 21 para local_auth
        targetSdk = 35
        versionCode = 2
        versionName = "2.3.1"
    }

    signingConfigs {
        create("release") {
            // Verifica que el archivo esté realmente en esa ruta
            storeFile = file("../ziro-keystore.jks")
            storePassword = "ziro123"
            keyAlias = "ziro-key"
            keyPassword = "ziro123"
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            // Para la Play Store, es mejor activar esto luego,
            // pero por ahora déjalos en false para que no te den errores de compilación.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
