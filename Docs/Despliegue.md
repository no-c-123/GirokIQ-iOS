# Despliegue automático a TestFlight

El job `deploy` de `.github/workflows/ci.yml` publica en TestFlight cada push a
`main`, siempre que las pruebas hayan pasado. Un build que falla sus pruebas no
llega a ningún tester: `needs: test` más `needs.test.result == 'success'`.

## Qué hace, paso por paso

1. **Selecciona Xcode** y falla con un mensaje claro si el runner no trae uno
   suficientemente nuevo.
2. **Instala la API key** de App Store Connect, decodificándola desde un secret
   hacia `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`, que es la ruta y
   el nombre exactos donde `altool` la busca.
3. **Archiva** con `-allowProvisioningUpdates`, pasando la API key a
   `xcodebuild`. Esto permite que Xcode obtenga o cree los activos de firma por
   sí mismo, de modo que **no hay que guardar el certificado de distribución ni
   el perfil de aprovisionamiento como secretos**.
4. **Exporta** el `.ipa` con `method = app-store-connect`.
5. **Valida** el build con `altool --validate-app` antes de subirlo. La
   validación detecta la mayoría de los rechazos (entitlements, iconos,
   `Info.plist`) sin consumir un número de build.
6. **Sube** el build con `altool --upload-app`.
7. **Guarda el `.ipa`** como artefacto durante 30 días.

## Secrets necesarios

Los tres se generan en App Store Connect → **Usuarios y acceso** →
**Integraciones** → **Claves de API App Store Connect**, con rol *App Manager*
o superior.

| Secret | Qué es | Cómo obtenerlo |
| --- | --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | Identificador de la clave, 10 caracteres | Aparece en la tabla de claves |
| `APP_STORE_CONNECT_ISSUER_ID` | UUID del emisor, común a toda la cuenta | Encima de la tabla de claves |
| `APP_STORE_CONNECT_KEY_P8` | El archivo `.p8` en base64 | Ver abajo |

El archivo `.p8` **solo se puede descargar una vez**. Guárdalo en un lugar
seguro antes de convertirlo.

```bash
# Genera el valor del secret APP_STORE_CONNECT_KEY_P8
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
```

Y para registrar los tres secretos, cada comando pide el valor de forma
interactiva:

```bash
gh secret set APP_STORE_CONNECT_KEY_ID --repo no-c-123/GirokIQ-iOS
gh secret set APP_STORE_CONNECT_ISSUER_ID --repo no-c-123/GirokIQ-iOS
gh secret set APP_STORE_CONNECT_KEY_P8 --repo no-c-123/GirokIQ-iOS
```

## Número de build

App Store Connect rechaza un número de build que ya haya visto. El pipeline
sobrescribe `CURRENT_PROJECT_VERSION` con el número de ejecución del workflow,
que solo puede aumentar. `MARKETING_VERSION` (1.0) se mantiene y se sube a mano
cuando corresponda a una versión nueva.

## Después de la subida

App Store Connect procesa el build entre 5 y 30 minutos. Luego:

- **Testers internos** (hasta 100, de tu propio equipo): lo reciben de inmediato,
  sin revisión de Apple.
- **Testers externos**: requieren *Beta App Review* la primera vez.

## Requisitos previos

- El registro de la app debe existir en App Store Connect con el bundle
  identifier `com.hectorleal.GirokIQ-ios`.
- El equipo `965LN23U3C` debe tener una membresía del Apple Developer Program
  activa.

## Cuando falle

| Síntoma | Causa habitual |
| --- | --- |
| `No signing certificate "iOS Distribution" found` | La clave de API no tiene rol suficiente, o el equipo alcanzó el límite de tres certificados de distribución |
| `The bundle version must be higher than the previously uploaded version` | Se reintentó una ejecución antigua; basta relanzar el workflow para obtener un número nuevo |
| `Invalid Provisioning Profile` | Falta un capability en el registro de la app (por ejemplo In-App Purchase) |
| `Authentication failed` | El `.p8` se copió con saltos de línea o se codificó mal; regenerar con `base64 -i` |
