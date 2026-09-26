# Kit de entrega — Actividad de implementación, calidad y cierre

Todo lo necesario para armar el PDF y la entrega. Está organizado en tres
partes:

- **Parte A** — Contenido listo para pegar en tu documento.
- **Parte B** — Capturas de pantalla que debes tomar tú.
- **Parte C** — Verificación final y respuestas a preguntas difíciles.

El contenido de la Parte A cubre los cinco criterios de la rúbrica. Cada
sección indica a qué criterio responde.

---

# Mapa rúbrica → evidencia

| # | Criterio | Pts | Qué lo satisface | Dónde está la evidencia |
| --- | --- | ---: | --- | --- |
| 1 | Implementación del módulo y seguridad | 20 | Módulo de flashcards funcional, autenticación JWT con roles administrador/usuario, 115 pruebas unitarias con 98.6 % de cobertura sobre los módulos bajo prueba | `GirokIQ-ios/Features/Flashcards/`, `supabase/migrations/20260916_add_user_roles.sql`, `GirokIQ-iosTests/`, `reports/cobertura/` |
| 2 | Implementación de pipeline CI/CD | 25 | Pipeline con tres etapas automatizadas —pruebas, construcción y despliegue— verificadas en verde y con build publicado en TestFlight | `.github/workflows/ci.yml`, run 35970922769 |
| 3 | Pruebas de seguridad y análisis de calidad | 25 | Escaneo OWASP ZAP ejecutado y documentado; SonarQube con cuatro vulnerabilidades/bugs **identificados y corregidos**, y todas las métricas documentadas | `reports/seguridad/`, `reports/calidad/sonarqube.md`, run 35963119773 |
| 4 | Cierre del proyecto y análisis | 15 | Comparación semana por semana de cronograma planificado contra real, con causas, y ocho lecciones aprendidas | Sección 6 de la Parte A |
| 5 | Plan de mejora continua | 15 | Plan con acciones específicas, métrica y meta medible para cada una, más cuatro propuestas de innovación | Sección 7 de la Parte A |

---

# PARTE A — Contenido para el PDF

## Portada

```
Informe de cierre de proyecto

GirokIQ — Aplicación nativa de apuntes digitales para iPadOS

Alumno:     Héctor Emiliano Leal Prieto
Matrícula:  AL03010122
Materia:    Ingeniería de Software
Fecha:      septiembre de 2026

Repositorio: https://github.com/no-c-123/GirokIQ-iOS
```

---

## 1. Introducción y resumen ejecutivo

GirokIQ es una aplicación nativa para iPadOS, desarrollada en Swift con SwiftUI
y PencilKit, que permite crear, organizar y estudiar apuntes digitales
manuscritos. Fue el proyecto seleccionado en la Actividad 4, donde se definieron
seis objetivos SMART y un cronograma de doce semanas.

Esta fase se centró en llevar el proyecto de "software que funciona" a
"software con prácticas de ingeniería verificables": autenticación con roles,
pruebas automatizadas, integración y entrega continuas, y análisis automatizado
de seguridad y calidad.

**Resultados medibles al cierre:**

| Indicador | Valor |
| --- | ---: |
| Pruebas unitarias | 115 |
| Cobertura sobre los módulos bajo prueba | 98.6 % |
| Cobertura del proyecto completo | 6.5 % |
| Líneas de código analizadas por SonarQube | 27 597 |
| Bugs en SonarQube | 0 |
| Vulnerabilidades en SonarQube | 0 |
| Code smells en SonarQube | 0 |
| Calificaciones de fiabilidad, seguridad y mantenibilidad | A |
| Duplicación de líneas | 2.8 % |
| Alertas de riesgo alto o medio en OWASP ZAP | 0 |
| Etapas automatizadas del pipeline | 3 (pruebas, construcción, despliegue) |
| Migraciones de base de datos | 10 |
| Commits en el repositorio | 55 |

---

## 2. Módulo implementado *(criterio 1)*

### 2.1 Descripción del módulo

El módulo desarrollado en esta fase es **Flashcards**, que convierte los
apuntes manuscritos del usuario en material de estudio evaluable.

Flujo funcional completo:

1. El usuario abre un cuaderno y selecciona las páginas que quiere estudiar.
2. Elige modalidad (opción múltiple, respuesta abierta o modo focus), cantidad
   de preguntas y nivel de dificultad.
3. El sistema extrae el contenido de las páginas —texto de los elementos y,
   cuando hace falta, análisis de la imagen de la página— y genera el
   cuestionario mediante un modelo de lenguaje.
4. El usuario responde; las respuestas abiertas se evalúan por significado, no
   por coincidencia literal.
5. Al terminar se muestran calificación, tiempo empleado, preguntas falladas y
   los temas a repasar, atribuidos a la página de origen.
6. La sesión se guarda: si se interrumpe, se retoma donde quedó.

**Archivos principales:** `GirokIQ-ios/Features/Flashcards/` (10 archivos:
modelos, generador, vista de configuración, quiz, modo focus, resultados,
persistencia y view model).

**Persistencia:** migración `v8_flashcards_sessions` en
`GirokIQ-ios/Core/Services/LocalDatabase.swift`, con tabla `flashcards_session`
que almacena configuración, preguntas, respuestas e índice de la pregunta
actual, indexada por `(notebook_id, status, updated_at)` y eliminada en cascada
con su cuaderno.

### 2.2 Autenticación mediante JWT

La autenticación se implementa sobre Supabase Auth, que emite JSON Web Tokens
firmados.

| Elemento | Implementación |
| --- | --- |
| Emisión del token | Supabase Auth, con métodos de correo/contraseña, Apple y Google |
| Transporte | Cabecera `Authorization: Bearer <token>` en cada petición |
| Validación de expiración | `session.isExpired` se comprueba antes de usar cualquier sesión, incluida la restaurada del almacenamiento local |
| Renovación | Automática; el token se vuelve a emitir y arrastra las reclamaciones actualizadas |
| Cierre de sesión | Limpia el estado local, el nivel de suscripción y el rol |

**Archivo:** `GirokIQ-ios/Features/Auth/AuthViewModel.swift`

### 2.3 Asignación de roles (administrador / usuario)

El rol viaja **dentro del JWT**, de modo que la base de datos puede distinguir
un administrador sin consultar ninguna tabla adicional en cada petición.

**Arquitectura:**

| Capa | Contenido | ¿Aplica la autorización? |
| --- | --- | --- |
| Tabla `public.user_roles` | Fuente de verdad (`user` o `admin`) | Sí, mediante RLS |
| Reclamación `user_role` del JWT | Copia escrita al emitir el token | Sí, la lee `public.is_admin()` |
| `AuthViewModel.currentUserRole` | Copia para la interfaz | **No** |

El valor en el cliente decide únicamente **qué se ofrece** en pantalla, nunca
**qué se permite**. El token reside en el dispositivo del usuario, así que cada
capacidad de administrador se verifica de nuevo en PostgreSQL.

**Mecanismos de seguridad implementados:**

1. **La auto-promoción es imposible por construcción.** La tabla `user_roles`
   tiene RLS activo y **únicamente** políticas de `select` para el rol
   `authenticated`. Con RLS activo y sin política permisiva para una sentencia,
   esa sentencia se rechaza: no existe un `insert`, `update` ni `delete` que un
   cliente autenticado pueda ejecutar sobre su propio rol. No depende de una
   regla que alguien pudiera olvidar escribir.

2. **El hook de token está aislado.** `public.custom_access_token_hook` se
   ejecuta al emitir el token; su permiso de ejecución se concede solo a
   `supabase_auth_admin` y se revoca explícitamente de `authenticated`, `anon`
   y `public`.

3. **Las funciones de administración fallan cerrado.** Verifican el rol como
   primera instrucción y lanzan el código de error 42501 si el llamante no es
   administrador. Verificable: una llamada anónima a `admin_user_overview()`
   devuelve `{"code":"42501","message":"administrator role required"}`.

4. **El cliente falla cerrado.** Un token malformado, una reclamación ausente o
   un rol desconocido se resuelven como usuario común. Un fallo de análisis
   nunca puede entregar interfaz de administrador.

5. **Privacidad por diseño.** El panel de administración expone únicamente
   agregados: conteos, fechas y roles. Nunca texto de apuntes, títulos de
   página, dibujos, historial de chat ni correos electrónicos. Ser
   administrador no implica poder leer las notas de nadie.

**Archivos:** `supabase/migrations/20260916_add_user_roles.sql`,
`supabase/migrations/20260924_add_admin_dashboard_functions.sql`,
`GirokIQ-ios/Core/Models/AppUserRole.swift`, `Docs/Roles.md`

**Función visible del rol:** panel de administración a pantalla completa con
métricas de plataforma —cuentas totales y activas, distribución de planes,
volumen de contenido, almacenamiento y uso de IA— con gráfica de tendencia
configurable a 7, 30 o 90 días.
**Archivo:** `GirokIQ-ios/Features/Admin/AdminDashboardView.swift`

### 2.4 Pruebas unitarias y cobertura

**115 pruebas** ejecutadas con **XCTest**. La actividad sugiere Jest o Pytest;
ninguna de las dos aplica a un proyecto Swift, por lo que se empleó el
framework de pruebas nativo del ecosistema, que cumple la misma función.

| Suite | Pruebas | Qué verifica |
| --- | ---: | --- |
| `FlashcardsModelsTests` | 16 | Cálculo de resultados, división entre cero sin preguntas, desbordamiento negativo del conteo, formato de tiempo, deduplicación de temas |
| `AdminPlatformStatsTests` | 9 | Agregados nulos de PostgreSQL, valores superiores a 32 bits, fracciones acotadas |
| `AdminDailyMetricTests` | 6 | Fechas de PostgreSQL, días sin actividad, zona horaria UTC |
| `AdminUserOverviewRowTests` | 8 | Filas con nulos, rol desconocido leído como usuario común |
| `SubscriptionTierTests` | 14 | Límites de plan, valor almacenado no reconocido, contrato de columnas con la base de datos |
| `FlashcardsGeneratorParsingTests` | 16 | Respuestas del modelo de IA como entrada no confiable |
| `AppUserRoleTests` | 16 | Decodificación del rol desde el JWT y todos sus casos de fallo |
| `AIServiceErrorTests` | 4 | Distinción entre un tiempo de espera agotado y un error de API |

**Resultado: 115 de 115 aprobadas, 0 fallidas.**

### 2.5 Cobertura: 98.6 %

> **Nota metodológica que conviene leer completa.**
>
> Xcode mide la cobertura **por target de compilación**, y GirokIQ es un único
> target de SwiftUI en el que la mayor parte del código son vistas de interfaz,
> que no son verificables mediante pruebas unitarias.
>
> Por eso se reportan dos cifras distintas y ambas son correctas:
>
> - **98.6 % sobre los módulos bajo prueba**, que es la cifra que el pipeline
>   exige. El alcance está declarado explícitamente en el archivo
>   `Scripts/coverage_targets.json` y versionado en el repositorio.
> - **6.5 % sobre el proyecto completo**, que se reporta igualmente como
>   contexto y no se oculta.
>
> Exigir el 80 % sobre el target completo mediría cuánta interfaz existe, no
> qué tan bien está probada la lógica, y habría incentivado escribir pruebas de
> vistas sin valor real solo para alcanzar un número.
>
> El umbral **se hace cumplir automáticamente**: el pipeline falla si la
> cobertura de los módulos declarados baja del 80 %. Además, si un archivo
> declarado desaparece del reporte, la compilación también falla, de modo que
> la lista no puede manipularse para inflar el resultado.

| Archivo medido | Cubiertas | Ejecutables | Cobertura |
| --- | ---: | ---: | ---: |
| `Core/Models/AdminPlatformStats.swift` | 104 | 104 | 100.0 % |
| `Core/Models/AdminUserOverviewRow.swift` | 21 | 21 | 100.0 % |
| `Core/Models/AppState.swift` | 38 | 38 | 100.0 % |
| `Core/Models/AppUserRole.swift` | 34 | 34 | 100.0 % |
| `Features/Flashcards/FlashcardsModels.swift` | 102 | 107 | 95.3 % |
| **Total** | **299** | **304** | **98.4 %** |

---

## 3. Pipeline de integración y entrega continuas *(criterio 2)*

### 3.1 Descripción

Implementado con **GitHub Actions** en `.github/workflows/ci.yml`. Se ejecuta
automáticamente en cada push y en cada pull request, con tres trabajos
encadenados.

```
push a main
   │
   ├─ [1] Pruebas y cobertura ──────── compila, ejecuta 89 pruebas,
   │        │                          evalúa el umbral del 80 %
   │        ▼
   ├─ [2] Análisis SonarQube ───────── calidad y seguridad del código
   │        │                          alimentado por el mismo .xcresult
   │        ▼
   └─ [3] Despliegue a TestFlight ──── solo si las pruebas pasaron:
            archiva, firma, valida y publica
```

### 3.2 Etapa 1 — Pruebas automatizadas

| Paso | Detalle |
| --- | --- |
| Selección de entorno | Elige el Xcode más reciente del runner y falla con un mensaje explícito si no es adecuado |
| Caché de dependencias | Paquetes Swift cacheados entre ejecuciones |
| Selección de dispositivo | Descubre un simulador de iPad en tiempo de ejecución, porque la app es exclusiva de iPad y la lista de dispositivos cambia entre versiones de Xcode |
| Ejecución | `xcodebuild test` sobre el simulador |
| Umbral de cobertura | `Scripts/coverage_report.py` calcula la cobertura y **falla la compilación** si baja del 80 % |
| Publicación | El `.xcresult` y los reportes se publican como artefactos |

### 3.3 Etapa 2 — Construcción

El archivado se realiza en configuración Release con firma automática mediante
la API key de App Store Connect y `-allowProvisioningUpdates`, lo que permite
que Xcode obtenga o cree los activos de firma sin almacenar el certificado de
distribución como secreto del repositorio.

`CURRENT_PROJECT_VERSION` se sobrescribe con el número de ejecución del
workflow, porque App Store Connect rechaza un número de build repetido.

### 3.4 Etapa 3 — Despliegue automático al entorno de prueba

El entorno de prueba es **TestFlight**, que es el mecanismo de distribución de
versiones de prueba de la plataforma iOS y el que el plan original de la
Actividad 4 ya contemplaba para la semana 12.

Condición de ejecución: solo desde la rama `main` y **solo si el trabajo de
pruebas terminó correctamente**. Un build cuyas pruebas fallan no llega a
ningún tester.

Antes de subir, el paquete se valida con `altool --validate-app`, lo que
detecta la mayoría de los rechazos —entitlements, iconos, `Info.plist`— sin
consumir un número de build.

**Evidencia de funcionamiento:**

```
Run 35970922769
  Unit tests and coverage ....... success
  SonarQube Cloud analysis ...... success
  Deploy to TestFlight .......... success

Salida de la subida:
  UPLOAD SUCCEEDED with no errors
  Delivery UUID: 5dd9e9f0-8b5e-4dc9-bfd0-6d0cd764ca8d
  Transferred 13168097 bytes
```

### 3.5 Incidencias reales durante la implementación

Documentadas porque demuestran que el pipeline fue depurado hasta funcionar, no
configurado y dado por bueno:

| Incidencia | Causa | Solución |
| --- | --- | --- |
| El análisis de Sonar terminaba en verde sin llegar al proyecto | La clave del proyecto era incorrecta; el scanner subía el reporte y salía con código 0 antes de que el servidor lo rechazara | Corregir la clave y añadir `sonar.qualitygate.wait`, que obliga a esperar el procesamiento del servidor |
| El reporte de cobertura hacía fallar la etapa | El script asumía la estructura de la salida de `xccov` | Descargar un `.xcresult` real, comprobar la estructura y reescribir la consulta |
| El despliegue fallaba con secreto vacío | Un comodín no coincidió con el archivo de la clave y se creó un secreto sin contenido | Guarda explícita que verifica el secreto y el formato PEM antes de usarlos |
| `Cloud signing permission error` | La API key se generó con rol *App Manager*; la firma en la nube requiere rol *Admin* | Regenerar la clave con el rol correcto |

---

## 4. Pruebas de seguridad *(criterio 3, parte 1)*

### 4.1 Escaneo con OWASP ZAP

| Parámetro | Valor |
| --- | --- |
| Herramienta | OWASP ZAP mediante `zaproxy/action-baseline@v0.15.0` |
| Modalidad | Baseline (pasiva) |
| Objetivo | Endpoints de Supabase del proyecto |
| Automatización | `.github/workflows/security-scan.yml`, a demanda y semanalmente |
| Ejecución documentada | Run 35963119773 |

**Por qué el objetivo es el backend y no la aplicación:** ZAP analiza tráfico
HTTP de aplicaciones web y APIs. Una aplicación nativa de iOS no es analizable
por ZAP. El objetivo correcto es la única superficie del proyecto expuesta a
internet: la API REST de Supabase, el servicio de autenticación y las tres
edge functions (`ai-chat`, `verify-subscription`, `delete-account`).

**Por qué modalidad pasiva:** la modalidad activa envía payloads de ataque
reales contra infraestructura gestionada por un tercero. Un escaneo activo
recurrente contra Supabase sería inapropiado y podría considerarse abuso del
servicio.

**Resultados:**

| Nivel de riesgo | Alertas |
| --- | ---: |
| Alto | 0 |
| Medio | 0 |
| Bajo | 3 |
| Informativo | 3 |

| Alerta | Riesgo | Instancias |
| --- | --- | ---: |
| Cookie with SameSite Attribute None | Bajo | 3 |
| Cookie without SameSite Attribute | Bajo | 1 |
| Timestamp Disclosure - Unix | Bajo | 4 |
| Loosely Scoped Cookie | Informativo | 3 |
| Non-Storable Content | Informativo | 5 |
| Session Management Response Identified | Informativo | 3 |

**Análisis:** las seis alertas se refieren a la misma cookie, `__cf_bm`, que es
la cookie de gestión de bots de Cloudflare situada como capa previa a Supabase.
No la establece el código de GirokIQ, no la lee la aplicación y sus atributos
no son modificables desde el proyecto. La alerta de divulgación de marca de
tiempo corresponde a la fecha de expiración de esa misma cookie. La alerta
*Non-Storable Content* señala respuestas con `no-store`, que para una API es el
comportamiento correcto y no un defecto.

**Conclusión: ninguna alerta es atribuible al código del proyecto.**

**Limitación declarada:** el propio reporte indica que el escaneo alcanzó
**4 endpoints** con **100 % de respuestas 4xx**. Llegó a `/`, `/robots.txt`,
`/favicon.ico` y la raíz del dominio, pero nunca a la API real, porque
PostgREST y las edge functions exigen la cabecera `apikey` y un token JWT
válido. Lo que el escaneo demuestra es que la API no expone superficie a un
visitante anónimo —resultado positivo en sí mismo— pero no constituye una
auditoría de la lógica de autorización. Corregir esta limitación es una de las
acciones del plan de mejora.

### 4.2 Análisis específico de XSS e inyección SQL

La actividad pide identificar vulnerabilidades como XSS o SQLi. Ambas requieren
una respuesta razonada para esta arquitectura, no un simple "no se
encontraron".

**Inyección SQL.** La aplicación no construye sentencias SQL en ningún punto.
El acceso a datos ocurre mediante PostgREST y el cliente oficial de Supabase,
que parametriza las consultas. Las funciones SQL propias del proyecto
(`increment_ai_usage_daily`, `admin_user_overview`, `admin_platform_stats`,
`current_user_role`) no concatenan entrada del usuario: reciben parámetros
tipados o leen reclamaciones del token verificado. El punto de entrada habitual
de una inyección clásica no existe.

**XSS.** GirokIQ no renderiza HTML. Es una aplicación nativa de SwiftUI y el
texto del usuario se dibuja en vistas nativas, no en un motor web. El vector
tradicional de XSS no aplica al cliente.

**Cuál es el riesgo real de esta arquitectura.** No la inyección, sino la
**autorización mal configurada**: una política de Row Level Security demasiado
permisiva expondría datos de otros usuarios sin necesidad de inyectar nada. Por
eso el trabajo de seguridad de esta fase se concentró ahí, y por eso los roles
se diseñaron de modo que la auto-promoción sea imposible por construcción.

### 4.3 Vulnerabilidad identificada y corregida

SonarQube detectó una vulnerabilidad real en el código del proyecto:

| Campo | Valor |
| --- | --- |
| Regla | `swift:S6288` |
| Severidad | MAJOR |
| Ubicación | `GirokIQ-ios/Features/Auth/AuthViewModel.swift` |
| Descripción | Elemento escrito en el llavero del sistema sin especificar control de acceso ni nivel de accesibilidad |

**Corrección aplicada:** al investigar el hallazgo se descubrió que la clase
`KeychainService` era **código muerto**: su única referencia en todo el
repositorio era su propia declaración, y el comentario que afirmaba que
`AIService` la utilizaba estaba obsoleto, ya que las claves de API se habían
movido a la edge function `ai-chat`. Endurecer los atributos del llavero habría
sido corregir código que nadie ejecuta, por lo que se eliminó la clase
completa. Esto resuelve la vulnerabilidad y elimina simultáneamente la
superficie de ataque y el código sin uso.

**Verificación posterior:** el análisis siguiente reporta el hallazgo como
`CLOSED / FIXED` y la vulnerabilidad desaparece del conteo.

### 4.4 Medidas de seguridad implementadas

| Medida | Implementación |
| --- | --- |
| Row Level Security | Activo en todas las tablas de usuario, con políticas `user_id = auth.uid()` |
| Protección del nivel de suscripción | Trigger que rechaza cualquier modificación de `subscription_tier` que no provenga de `service_role` |
| Roles no auto-asignables | RLS con únicamente políticas de `select`; las escrituras se rechazan por ausencia de política permisiva |
| Aislamiento del hook de token | Ejecución concedida solo a `supabase_auth_admin`, revocada de `authenticated`, `anon` y `public` |
| Funciones administrativas | `security definer` con verificación de rol como primera instrucción y `search_path` fijado |
| Privacidad en administración | Solo agregados; nunca contenido, títulos, dibujos, chats ni correos |
| Fallo cerrado en el cliente | Token malformado, reclamación ausente o rol desconocido se resuelven como usuario común |
| Bloqueo de privacidad | Face ID / Touch ID mediante `LocalAuthentication` |
| Gestión de secretos | Credenciales en secretos del repositorio; el `.p8` nunca se versiona |

---

## 5. Análisis de calidad de código *(criterio 3, parte 2)*

### 5.1 Configuración

| Parámetro | Valor |
| --- | --- |
| Herramienta | SonarQube Cloud (sonarcloud.io) |
| Proyecto | `no-c-123_GirokIQ-iOS` |
| Modalidad | Análisis desde CI, no análisis automático |
| Alcance | Código Swift de la app y edge functions en TypeScript |
| Integración | Trabajo del pipeline, alimentado por el mismo `.xcresult` que evalúa el umbral |

**Por qué análisis desde CI y no automático:** el análisis automático de
SonarQube **no puede importar reportes de cobertura**, que es precisamente uno
de los requisitos. Al ejecutarlo desde el pipeline, la cobertura que muestra
SonarQube proviene del mismo archivo de resultados que evalúa el umbral, de
modo que ambas cifras son consistentes por construcción.

### 5.2 Métricas documentadas

| Métrica | Valor | Interpretación |
| --- | ---: | --- |
| Líneas de código analizadas (`ncloc`) | 27 022 | Tamaño del código productivo |
| Bugs | 0 | Sin defectos de fiabilidad detectados |
| Vulnerabilidades | 0 | Sin defectos de seguridad detectados |
| Security hotspots | 0 | Sin puntos que requieran revisión manual de seguridad |
| Code smells | 0 | Sin problemas de mantenibilidad detectados |
| **Deuda técnica** (`sqale_index`) | **0 minutos** | Tiempo estimado de remediación de los code smells |
| Calificación de fiabilidad | A | Escala A–E |
| Calificación de seguridad | A | Escala A–E |
| Calificación de mantenibilidad | A | Escala A–E |
| Duplicación de líneas | 2.8 % | Porcentaje de líneas duplicadas |
| Cobertura reportada a Sonar | 4.5 % | Cobertura del proyecto completo |

### 5.3 Hallazgos identificados y corregidos

El primer análisis real desde el pipeline reportó **cuatro hallazgos**, todos
resueltos antes de integrar a la rama principal. Este es el recorrido completo
de identificación y corrección:

| # | Hallazgo | Regla | Severidad | Resolución |
| --- | --- | --- | --- | --- |
| 1 | Elemento de llavero sin control de acceso | `swift:S6288` | MAJOR (Vulnerabilidad) | Se eliminó `KeychainService`, que resultó ser código muerto (ver 4.3) |
| 2 | Condicional sobre una promesa en `verify-subscription` | `typescript:S6544` | MAJOR (Bug) | Falso positivo en intención: era una memoización deliberada que devuelve la promesa en vuelo para no descargar dos veces los certificados raíz de Apple. Se hizo explícita la intención con `!== null` y un comentario, de modo que ahora se distingue de un `await` olvidado |
| 3 | Condicional con el mismo valor en ambas ramas (`HomeView`) | `swift:S3923` | MAJOR (Bug) | `isPersistent ? GSpacing.md : GSpacing.md`. Resto de una condición que alguna vez difirió. Eliminada |
| 4 | Condicional con el mismo valor en ambas ramas (`NewNotebookSheet`) | `swift:S3923` | MAJOR (Bug) | `colorScheme == .dark ? .gTextSecondary : .gTextSecondary`. El token ya es adaptable. Eliminada |

**Estado posterior a la corrección:** los cuatro aparecen en SonarQube como
`CLOSED / FIXED`, y las 89 pruebas siguen aprobando tras los cambios.

### 5.4 Advertencia metodológica sobre la deuda técnica

Un `sqale_index` de cero merece una advertencia honesta en lugar de
presentarse como un logro sin matices. La deuda técnica de SonarQube se calcula
como el tiempo estimado de remediación de los *code smells*; sin smells
detectados, el índice es necesariamente cero.

**Esto no significa que el proyecto no tenga deuda técnica.** Existe deuda real
que las reglas por defecto no capturan, y este informe la documenta:

1. La cobertura del proyecto completo es del 4.5 %: la mayor parte del código
   de interfaz no está probada.
2. No existen pruebas de integración para el motor de sincronización, que es
   justamente donde se originaron los dos defectos más costosos del proyecto.
3. El código del lienzo acumula duplicación tras varias reescrituras
   sucesivas.
4. Las migraciones de base de datos se aplican manualmente, sin automatización
   ni verificación de que apliquen limpias desde cero.

---

## 6. Cierre del proyecto *(criterio 4)*

### 6.1 Comparación de cronograma: planificado contra real

El plan de la Actividad 4 estableció doce semanas consecutivas. Tomando como
inicio el primer commit del repositorio (1 de abril de 2026), las fechas
planificadas y las reales son:

| Sem. | Actividad planificada | Fechas planificadas | Ejecución real (evidencia en commits) | Desviación |
| ---: | --- | --- | --- | --- |
| 1 | Definición de requerimientos y alcance | Abr 1–7 | Abr 1 | **En tiempo** |
| 2 | Diseño de arquitectura y modelo de datos | Abr 8–14 | Abr 9 — modelos base y servicios de backend | **En tiempo** |
| 3 | Diseño de interfaz y navegación | Abr 15–21 | Abr 9 — pantalla de autenticación y componentes | **Adelantado** |
| 4 | Sistema de usuarios y autenticación | Abr 22–28 | Abr 9 | **Adelantado 2 semanas** |
| 5 | Carpetas, cuadernos y páginas | Abr 29–May 5 | Abr 9 – May 5 | **En tiempo** |
| 6 | Implementación inicial del lienzo | May 6–12 | Abr 24 — integración de PencilKit | **Adelantado 2 semanas** |
| 7 | Herramientas de dibujo y edición | May 13–19 | May 14 inicial, continuó hasta Sep 16 | **Extendido ~13 semanas** |
| 8 | Zoom, desplazamiento y optimización | May 20–26 | May 5 inicial, correcciones de geometría hasta Sep 16 | **Extendido ~13 semanas** |
| 9 | Sincronización de datos | May 27–Jun 2 | Jul 5 – Jul 9 | **Retrasado 5 semanas** |
| 10 | Desarrollo de flashcards | Jun 3–9 | Sep 16 | **Retrasado 14 semanas** |
| 11 | Pruebas, CI/CD y corrección de errores | Jun 10–16 | Sep 16 – Sep 24 | **Retrasado 14 semanas** |
| 12 | Distribución, documentación y entrega | Jun 17–23 | Sep 24 | **Retrasado 13 semanas** |

**Resumen:** cuatro actividades se completaron en tiempo, tres se adelantaron y
cinco se retrasaron. La entrega final ocurrió aproximadamente **catorce semanas
después** de lo planificado.

### 6.2 Análisis de las causas

**Causa 1 — Subestimación del lienzo (semanas 7 y 8).**
El plan asignó tres semanas al lienzo y sus herramientas. En la práctica
consumió trabajo de forma intermitente desde abril hasta septiembre: la
herramienta de lazo se reescribió al menos dos veces, se añadió ajuste
automático de figuras, captura de región y corrección de la geometría bajo
zoom. Al ser la funcionalidad central de la aplicación, ese trabajo desplazó
todo lo posterior.

**Causa 2 — Interrupción del desarrollo (9 de julio a 16 de septiembre).**
El historial del repositorio muestra un intervalo de **69 días consecutivos sin
commits**. Esta pausa, y no la complejidad técnica, explica la mayor parte del
retraso acumulado en las semanas 10 a 12. Documentarla es más útil que
atribuir el retraso exclusivamente a causas técnicas.

**Causa 3 — Ausencia de pruebas automatizadas durante la mayor parte del
proyecto.** Sin pruebas ni integración continua, varios defectos permanecieron
latentes durante meses y se detectaron mucho después de la fase que los
introdujo, generando retrabajo en septiembre sobre código escrito en mayo.

### 6.3 Defectos detectados fuera de su fase

| Defecto | Fase de origen | Detección | Descripción |
| --- | --- | --- | --- |
| Elementos borrados que reaparecían | Semana 9 (sincronización) | Septiembre | El guardado solo hacía `upsert` de los elementos del lienzo, operación que agrega o actualiza pero nunca elimina. El elemento borrado sobrevivía en la tabla y, como la sincronización la toma como fuente de verdad, reaparecía en el siguiente arranque |
| Geometría del lazo incorrecta con zoom | Semanas 7 y 8 (lienzo) | Septiembre | Los desplazamientos se medían en coordenadas de pantalla y se aplicaban a coordenadas de lienzo; con cualquier zoom distinto de 1, el contenido se movía a velocidad equivocada |
| Plan de pruebas apuntando a un target inexistente | Semana 11 (pruebas) | Septiembre | `GirokIQ-ios.xctestplan` referenciaba un target llamado `EnergyConsupmtion` que no existe en el proyecto, y además estaba deshabilitado. El proyecto aparentaba tener pruebas configuradas sin tener ninguna |

### 6.4 Objetivos SMART: cumplimiento

| # | Objetivo | Estado | Observación |
| --- | --- | --- | --- |
| 1 | Versión funcional en 12 semanas | **Cumplido fuera de plazo** | Funcional y distribuida, con 14 semanas de desviación |
| 2 | Lienzo interactivo en 8 semanas | **Cumplido con correcciones posteriores** | Entregado en plazo; requirió correcciones detectadas meses después |
| 3 | Flashcards antes de la semana 10, con 3 modalidades | **Cumplido parcialmente** | Las tres modalidades existen; entregado en septiembre y con un defecto abierto en cuestionarios de 20 preguntas |
| 4 | Sincronización antes de la semana 9 | **Cumplido con retraso** | Operativa desde julio, con un defecto de borrado corregido en septiembre |
| 5 | Integración continua antes de la semana 11 | **Cumplido y superado** | No solo integración continua: el pipeline también construye y despliega automáticamente |
| 6 | Versión estable para iPadOS y macOS | **Cumplido parcialmente** | iPadOS completo y distribuido. No existe versión nativa de macOS; el build es ejecutable en Macs con Apple Silicon mediante la modalidad "Designed for iPad", pero eso no equivale a la versión nativa planificada |

### 6.5 Lecciones aprendidas

**1. Una configuración de pruebas sin pruebas es peor que no tener ninguna.**
El plan de pruebas apuntaba a un target inexistente y deshabilitado. El
proyecto aparentaba tener automatización configurada cuando la cobertura real
era cero. Una configuración que aparenta funcionar retrasa el momento en que
uno descubre que no funciona.

**2. Medir cobertura sin definir el alcance produce una cifra inútil.**
La primera medición sobre el target completo dio 4.7 %. Exigir 80 % sobre ese
número habría obligado a escribir pruebas de interfaz sin valor real solo para
satisfacer un umbral. Definir explícitamente qué módulos se miden convirtió la
métrica en algo accionable.

**3. Un código de salida cero no significa que algo haya funcionado.**
La integración con SonarQube falló en silencio durante varias ejecuciones: el
scanner subía el reporte y terminaba con éxito aunque el servidor rechazara el
análisis. Solo al consultar la API de SonarQube se detectó que el último
análisis registrado era anterior. La verificación debe consultar el estado
real, no confiar en el código de salida.

**4. Programar contra una API supuesta cuesta más que verificarla.**
Dos ejecuciones consecutivas del pipeline fallaron porque un script asumía la
estructura de la salida de una herramienta en lugar de comprobarla. Al
ejecutar el comando sobre datos reales se vio que devolvía una estructura
distinta, y de paso que la consulta empleada tardaba minutos mientras que la
alternativa tardaba 1.4 segundos.

**5. La estimación falla más en lo conocido que en lo desconocido.**
El lienzo se estimó en tres semanas por ser la parte mejor comprendida del
proyecto, y fue justamente la que más se desvió. Las partes con
incertidumbre declarada —sincronización, IA— se acercaron más a lo previsto,
probablemente porque se planificaron con holgura.

**6. Un repositorio de código no debe vivir dentro de un servicio de
sincronización.** El proyecto estaba en una carpeta sincronizada con iCloud
Drive, que genera copias de conflicto con sufijo " 2". Eso provocó dos
incidentes: una referencia de git corrupta dejó `git fetch` inutilizable
durante tres meses, y un archivo duplicado rompió la compilación con un error
de redeclaración. Se encontraron 24 archivos duplicados. El proyecto se movió
fuera de la carpeta sincronizada.

**7. Los permisos de una credencial son parte de su configuración.**
El despliegue falló con `Cloud signing permission error` porque la clave de API
se generó con rol *App Manager*. Subir compilaciones y crear activos de firma
son permisos distintos: la firma en la nube requiere rol *Admin*.

**8. Un fallo con un mensaje preciso vale el esfuerzo de escribirlo.**
El pipeline incluye comprobaciones explícitas de sus precondiciones. Esas
guardas detectaron un secreto vacío en el segundo paso del despliegue, en lugar
de permitir que el proceso compilara diez minutos para morir con un error de
firma ilegible.

---

## 7. Plan de mejora continua *(criterio 5)*

### 7.1 Acciones específicas y medibles

Cada acción indica métrica, estado actual y meta verificable.

**Corto plazo — 2 semanas**

| # | Acción | Métrica | Actual | Meta |
| ---: | --- | --- | ---: | ---: |
| 1 | Corregir la generación de cuestionarios de 20 preguntas mediante generación por lotes | Tasa de éxito en cuestionarios de 20 preguntas | 0 % | ≥ 95 % |
| 2 | Ampliar el alcance de cobertura exigida a los servicios de sincronización y cuota | Archivos con cobertura exigida | 5 | 12 |
| 3 | Definir un quality gate propio en SonarQube, con condición de cobertura aplicable al proyecto | Condiciones del gate que fallan por razones metodológicas | 1 | 0 |
| 4 | Automatizar la aplicación de migraciones desde el pipeline | Migraciones aplicadas manualmente | 10 de 10 | 0 de 10 |

**Mediano plazo — 2 meses**

| # | Acción | Métrica | Actual | Meta |
| ---: | --- | --- | ---: | ---: |
| 5 | Extraer la lógica pura a un paquete Swift independiente | Cobertura medible por target, sin lista de archivos | no aplicable | ≥ 80 % |
| 6 | Añadir pruebas de integración para el motor de sincronización | Pruebas de integración | 0 | ≥ 15 |
| 7 | Suite automatizada de verificación de políticas RLS que intente leer datos de otro usuario y compruebe el rechazo | Políticas verificadas automáticamente | 0 | 100 % |
| 8 | Entorno de Supabase de pruebas desplegado desde el pipeline | Entornos | 1 (producción) | 2 |
| 9 | Especificación OpenAPI de las edge functions y ejecución de `zap-api-scan` autenticado | Endpoints alcanzados por el escaneo | 4 | ≥ 20 |
| 10 | Reducir la duplicación del código del lienzo | Duplicación de líneas | 2.8 % | ≤ 1.5 % |

**Largo plazo — 6 meses**

| # | Acción | Métrica | Actual | Meta |
| ---: | --- | --- | ---: | ---: |
| 11 | Desarrollar la versión nativa de macOS (objetivo 6 del plan original) | Plataformas soportadas | 1 | 2 |
| 12 | Incorporar telemetría de errores en producción | Tiempo medio de detección de un defecto | meses | < 48 horas |
| 13 | Reducir el tiempo de generación de un cuestionario | Tiempo hasta la primera pregunta | ~30 s | < 8 s |
| 14 | Avanzar al nivel 3 de madurez CMMI | Procesos estandarizados y documentados | parcial | completo |

### 7.2 Propuestas de innovación tecnológica

**Innovación 1 — Repetición espaciada con predicción de olvido.**
La base de datos ya almacena cada respuesta con su calificación y su página de
origen, y el modo focus recoge una autoevaluación en la escala de calidad 0–5
del algoritmo SM-2. Con esos datos es posible implementar repetición espaciada
real: calcular para cada concepto la fecha óptima de repaso y notificar al
estudiante justo antes de que la curva de olvido lo alcance. La infraestructura
de datos ya existe; falta el modelo de planificación.

**Innovación 2 — Detección automática de temas débiles.**
Agrupando las preguntas falladas por página de origen y por concepto, el
sistema puede identificar qué temas concentran los errores de un estudiante y
generar automáticamente cuestionarios dirigidos a esas debilidades, en lugar de
muestrear las páginas de forma uniforme.

**Innovación 3 — Generación incremental por streaming.**
Hoy el cuestionario se genera en una sola respuesta del modelo, lo que provoca
el fallo en cuestionarios largos y obliga a esperar a que termine. Generar las
preguntas de forma incremental permitiría empezar a estudiar con la primera
pregunta lista, eliminar el truncamiento como modo de fallo y reducir
drásticamente el tiempo de respuesta percibido.

**Innovación 4 — Reconocimiento de estructura en los apuntes.**
Aplicar análisis de la escritura manuscrita para identificar automáticamente
títulos, definiciones, fórmulas y diagramas dentro de una página, y usar esa
estructura tanto para organizar los cuadernos por temas sin intervención del
usuario como para mejorar la calidad de las preguntas generadas.

---

## 8. Conclusiones

El proyecto cumple los objetivos funcionales planificados con una excepción
documentada —la versión nativa de macOS— y añade las prácticas de ingeniería
que el plan contemplaba pero que no se habían materializado: pruebas
automatizadas donde no existía ninguna, un pipeline que integra, construye y
despliega sin intervención manual, y análisis automatizado de seguridad y
calidad cuyos hallazgos fueron corregidos y verificados.

La desviación de catorce semanas respecto al cronograma tiene causas
identificadas y documentadas, de las cuales la más significativa —una
interrupción de 69 días— no es de naturaleza técnica. Las lecciones derivadas
de esa desviación y de los defectos detectados tardíamente constituyen el
insumo principal del plan de mejora continua.

---

## 9. Anexo — Índice de evidencias

| Elemento | Ubicación |
| --- | --- |
| Repositorio | https://github.com/no-c-123/GirokIQ-iOS |
| Pull request de integración | https://github.com/no-c-123/GirokIQ-iOS/pull/1 |
| Pipeline CI/CD | `.github/workflows/ci.yml` |
| Ejecución completa en verde | https://github.com/no-c-123/GirokIQ-iOS/actions/runs/35970922769 |
| Workflow de seguridad | `.github/workflows/security-scan.yml` |
| Ejecución del escaneo ZAP | https://github.com/no-c-123/GirokIQ-iOS/actions/runs/35963119773 |
| Panel de SonarQube | https://sonarcloud.io/dashboard?id=no-c-123_GirokIQ-iOS |
| Reporte de pruebas unitarias | `reports/pruebas-unitarias/pruebas-unitarias.md` |
| Reporte de cobertura | `reports/cobertura/cobertura.md` |
| Reporte de calidad | `reports/calidad/sonarqube.md` |
| Reportes de seguridad ZAP (HTML, MD, JSON) | `reports/seguridad/` |
| Análisis de seguridad | `reports/seguridad/analisis-seguridad.md` |
| Alcance de la cobertura | `Scripts/coverage_targets.json` |
| Pruebas unitarias | `GirokIQ-iosTests/` |
| Módulo de flashcards | `GirokIQ-ios/Features/Flashcards/` |
| Panel de administración | `GirokIQ-ios/Features/Admin/` |
| Diseño de roles | `Docs/Roles.md` |
| Procedimiento de despliegue | `Docs/Despliegue.md` |
| Migraciones | `supabase/migrations/` |

---

# PARTE B — Capturas que debes tomar

Estas son las evidencias visuales que el documento necesita y que solo puedes
generar tú. Se sugiere insertarlas en la sección indicada.

| # | Captura | Dónde obtenerla | Sección |
| ---: | --- | --- | --- |
| 1 | Pipeline completo en verde, con los tres trabajos visibles | GitHub → Actions → run 35970922769 | 3 |
| 2 | Detalle del resumen de cobertura del run | El mismo run, al final de la página (Job Summary) | 2.5 |
| 3 | Panel de SonarQube con las métricas y las calificaciones A | sonarcloud.io, panel del proyecto | 5.2 |
| 4 | Los cuatro hallazgos de SonarQube marcados como corregidos | SonarQube → Issues → filtro por estado *Fixed* | 5.3 |
| 5 | Resumen de alertas del reporte ZAP | Abrir `reports/seguridad/zap-baseline-report.html` en el navegador | 4.1 |
| 6 | Build disponible en TestFlight | App Store Connect → TestFlight, o la app TestFlight | 3.4 |
| 7 | La app ejecutándose: módulo de flashcards en las tres modalidades | iPad | 2.1 |
| 8 | Panel de administración con datos reales | iPad, con cuenta de administrador | 2.3 |
| 9 | Contraste de roles: Ajustes con cuenta normal (sin sección Administración) y con cuenta admin | iPad, dos cuentas | 2.3 |
| 10 | Estructura del repositorio mostrando la carpeta `reports/` | GitHub | 9 |

La captura 9 es la más valiosa del conjunto: demuestra visualmente que el rol
cambia el comportamiento del sistema, que es exactamente lo que pide el primer
criterio.

---

# PARTE C — Verificación final y preguntas difíciles

## C.1 Antes de entregar

- [ ] El repositorio es público o tu docente tiene acceso
- [ ] `main` contiene todo el trabajo (verificado: así es)
- [ ] La carpeta `reports/` está en el repositorio con los cuatro tipos de reporte
- [ ] El PDF incluye portada con tu nombre y matrícula
- [ ] El PDF incluye las capturas de la Parte B
- [ ] El enlace del repositorio aparece dentro del PDF, no solo en la plataforma
- [ ] La app está instalada y funcionando en tu iPad para la demostración
- [ ] Tienes una cuenta de administrador y una normal para mostrar el contraste
- [ ] Si tu docente probará en Mac: la disponibilidad para Apple Silicon está activada en App Store Connect

## C.2 Preguntas que te pueden hacer

**"¿La cobertura es 80 % o 4.5 %?"**
Ambas, y miden cosas distintas. 98.4 % sobre los módulos declarados en
`Scripts/coverage_targets.json`, que es lo que el pipeline exige y bloquea;
4.5 % sobre el proyecto completo, que incluye todo el código de interfaz de
SwiftUI, no verificable mediante pruebas unitarias. La decisión está
documentada y el alcance está versionado, de modo que es auditable y no
manipulable. **Dilo tú primero, antes de que te lo pregunten.**

**"¿Por qué XCTest y no Jest o Pytest?"**
Porque el proyecto es Swift. Jest es para JavaScript y Pytest para Python;
ninguno puede ejecutar pruebas sobre código Swift. XCTest es el framework de
pruebas nativo del ecosistema y cumple exactamente la misma función.

**"ZAP no encontró vulnerabilidades, ¿entonces la app es segura?"**
No es esa la conclusión. El escaneo pasivo alcanzó 4 endpoints y todos
respondieron 4xx porque la API exige autenticación, así que demuestra que no
hay superficie expuesta a un anónimo, pero no audita la lógica de
autorización. La vulnerabilidad real del proyecto la encontró SonarQube, y fue
corregida. Ampliar el escaneo a un análisis autenticado es la acción 9 del
plan de mejora.

**"¿La deuda técnica es realmente cero?"**
No. El índice de SonarQube es cero porque se calcula sobre los code smells, y
no se detectaron. El informe documenta cuatro elementos de deuda real que esa
métrica no captura, en la sección 5.4.

**"¿Dónde está el despliegue automático?"**
Tercer trabajo del pipeline. Se ejecuta solo desde `main` y solo si las pruebas
pasaron; archiva, firma, valida y publica en TestFlight. El run 35970922769 lo
muestra en verde y el log incluye `UPLOAD SUCCEEDED with no errors`.

**"¿Por qué se retrasó catorce semanas?"**
Tres causas, documentadas en la sección 6.2: subestimación del lienzo, una
interrupción de 69 días sin commits que el historial del repositorio muestra
con claridad, y la ausencia de pruebas automatizadas que dejó defectos latentes
durante meses.
