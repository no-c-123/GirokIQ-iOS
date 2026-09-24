# Informe de cierre — GirokIQ

**Alumno:** Héctor Emiliano Leal Prieto — AL03010122
**Proyecto:** GirokIQ, aplicación nativa de apuntes digitales para iPadOS
**Repositorio:** https://github.com/no-c-123/GirokIQ-iOS
**Fecha:** septiembre de 2026

---

## 1. Resumen ejecutivo

GirokIQ se planificó en la Actividad 4 como una aplicación nativa en Swift para
iPadOS, con seis objetivos SMART y un cronograma de doce semanas. Esta fase
añadió sobre esa base lo que faltaba en materia de calidad y seguridad:
autenticación con JWT ya existente ahora complementada con **roles de
administrador y usuario**, una **suite de pruebas unitarias** donde antes no
había ninguna, un **pipeline de integración continua** que ejecuta esas pruebas
y bloquea la integración si la cobertura cae, y análisis de **calidad de código**
y **seguridad**.

El resultado medible al cierre:

| Indicador | Valor |
| --- | --- |
| Pruebas unitarias | 74 |
| Cobertura sobre los módulos bajo prueba | 97.2 % |
| Cobertura del target completo | 4.7 % |
| Líneas de Swift en el proyecto | 31 136 en 77 archivos |
| Líneas analizadas por SonarQube | 8 828 |
| Migraciones de base de datos | 9 |
| Commits en la rama de esta fase | 28 |

El proyecto cumple los objetivos funcionales planificados con una excepción
clara —la versión para macOS no se entregó— y añade prácticas de ingeniería que
el plan contemplaba pero que no se habían materializado.

---

## 2. Comparación entre lo planificado y lo ejecutado

### 2.1 Objetivos SMART

| # | Objetivo planificado (Actividad 4) | Estado | Observaciones |
| --- | --- | --- | --- |
| 1 | Versión funcional en 12 semanas: carpetas, cuadernos, páginas y notas | **Cumplido** | Funcional y en uso. El desarrollo se extendió más allá de las 12 semanas previstas |
| 2 | Lienzo interactivo en las primeras 8 semanas: escritura, dibujo, selección, zoom, edición | **Cumplido con correcciones posteriores** | Entregado dentro del plazo, pero requirió correcciones de geometría detectadas meses después (ver 2.3) |
| 3 | Flashcards antes de la semana 10, con al menos tres modalidades | **Cumplido parcialmente** | Tres modalidades implementadas (opción múltiple, respuesta abierta, modo focus). Terminado en septiembre, no en la semana 10, y con un defecto abierto |
| 4 | Sincronización en la nube antes de la semana 9 | **Cumplido con correcciones posteriores** | Operativa, pero con un defecto de borrado detectado tarde (ver 2.3) |
| 5 | Flujo de integración continua antes de la semana 11 | **Cumplido fuera de plazo** | El pipeline existe y funciona, pero se implementó en septiembre. Antes de esta fase no había ninguna automatización |
| 6 | Versión estable para **iPadOS y macOS** al terminar la semana 12 | **Cumplido parcialmente** | La aplicación está limitada a iPad (`TARGETED_DEVICE_FAMILY = 2`). La versión para macOS no se desarrolló |

### 2.2 Cronograma

El cronograma original contemplaba doce semanas consecutivas a partir de abril
de 2026. El primer commit del repositorio es del **1 de abril de 2026** y el
trabajo de esta fase se concentra entre el **12 de junio** y el **23 de
septiembre de 2026**, es decir, aproximadamente **catorce semanas por encima de
lo planificado**.

La desviación no se distribuye de forma uniforme. Las semanas 1 a 9 (requisitos,
arquitectura, interfaz, autenticación, organización de contenido, lienzo y
sincronización) avanzaron de forma razonablemente cercana al plan. Las semanas
10 a 12 —flashcards, CI/CD y distribución— concentran prácticamente todo el
retraso.

La causa principal es que el esfuerzo real del lienzo se subestimó. El plan le
asignaba tres semanas (6, 7 y 8); en la práctica el lienzo siguió consumiendo
trabajo hasta septiembre, con varias reescrituras: refactorización del lazo,
ajuste de figuras, captura de región y corrección de la geometría bajo zoom.
Ese trabajo desplazó las semanas finales.

### 2.3 Defectos detectados fuera de su fase

Tres defectos relevantes se detectaron mucho después de la fase en que se
introdujeron, lo que ilustra el costo de no haber tenido pruebas automatizadas
desde el principio:

1. **Elementos borrados que reaparecían.** El guardado de páginas solo hacía
   `upsert` de los elementos del lienzo. Un `upsert` agrega o actualiza, pero
   nunca elimina, de modo que un elemento borrado sobrevivía en la tabla
   `canvas_elements` y, como la sincronización toma esa tabla como fuente de
   verdad, el elemento volvía a aparecer en el siguiente arranque. Corresponde
   a la semana 9 del plan y se corrigió en septiembre.

2. **Geometría del lazo incorrecta con zoom.** Los desplazamientos se medían en
   coordenadas de pantalla y se aplicaban a coordenadas de lienzo, de modo que
   con cualquier zoom distinto de 1 el contenido se movía a una velocidad
   equivocada. Corresponde a las semanas 7 y 8 y se corrigió en septiembre.

3. **Plan de pruebas apuntando a un target inexistente.** El archivo
   `GirokIQ-ios.xctestplan` referenciaba un target llamado `EnergyConsupmtion`
   que no existe en `project.pbxproj`, y además estaba deshabilitado. El
   proyecto aparentaba tener pruebas configuradas sin tener ninguna.

### 2.4 Elementos ejecutados que no estaban en el plan

| Elemento | Motivo |
| --- | --- |
| Roles de administrador y usuario | Requisito de esta actividad; no figuraba en la Actividad 4 |
| Análisis con SonarQube Cloud | Requisito de esta actividad |
| Escaneo de seguridad con OWASP ZAP | Requisito de esta actividad |
| Límite de tres cuadernos en el plan gratuito | Decisión de producto tomada durante la implementación |
| Suscripciones y control de almacenamiento | Derivado de la preparación para TestFlight |

### 2.5 Elemento planificado y pendiente

El plan incluía **distribución mediante TestFlight y App Store Connect**
(semana 12) y la actividad actual exige **despliegue automático a un entorno de
prueba**. El pipeline implementado compila, prueba y evalúa cobertura, pero
**no despliega**. La decisión fue consciente: se acordó posponer la etapa de
despliegue hasta que el módulo de flashcards dejara de cambiar, para no publicar
compilaciones de una funcionalidad inestable. Es la desviación más importante
que queda abierta respecto a los requisitos de esta fase.

---

## 3. Resultados de calidad y seguridad

### 3.1 Pruebas unitarias

74 pruebas en `GirokIQ-iosTests`, ejecutadas con **XCTest**. La actividad
sugería Jest o Pytest; ninguna de las dos aplica a un proyecto Swift, por lo que
se utilizó el equivalente nativo del ecosistema.

Las pruebas se concentran en la lógica que tiene sentido verificar de forma
aislada:

- Cálculo de resultados de flashcards, incluidos los casos límite: división
  entre cero cuando no hay preguntas, conteo negativo, formato de tiempo y
  deduplicación de temas a repasar.
- Límites del plan de suscripción y el contrato de nombres de columna con la
  tabla `app_state`.
- Interpretación de la respuesta del modelo de IA, que es entrada no confiable:
  bloques de código, texto conversacional alrededor del JSON, respuestas
  truncadas y disculpas del modelo que deben leerse como "sin texto".
- Decodificación del rol desde el JWT, con todos los casos de fallo.

**Cobertura: 97.2 %** sobre los módulos bajo prueba.

Es necesario explicar esta cifra con precisión. Xcode mide cobertura **por
target**, y GirokIQ es un único target de SwiftUI cuyas vistas no son
verificables mediante pruebas unitarias. Un umbral del 80 % sobre el target
completo mediría cuánta interfaz existe, no qué tan bien está probada la lógica.
Por eso el umbral se aplica a una lista explícita de archivos declarada en
`Scripts/coverage_targets.json`, y la cobertura del target completo (**4.7 %**)
se reporta igualmente como contexto. Un archivo declarado que desaparezca del
reporte hace fallar la compilación, de modo que la lista no puede manipularse
para inflar el resultado.

### 3.2 Integración continua

`.github/workflows/ci.yml` se ejecuta en cada push y en cada pull request:

1. Selecciona el Xcode más reciente del runner y falla con un mensaje explícito
   si es anterior al 26.2 que la aplicación requiere.
2. Descubre un simulador de iPad en tiempo de ejecución, ya que la aplicación
   es exclusiva de iPad y la lista de dispositivos cambia entre versiones.
3. Compila, ejecuta las pruebas y evalúa el umbral de cobertura.
4. Publica el reporte y el `.xcresult` como artefactos.

### 3.3 Calidad de código (SonarQube Cloud)

Métricas del análisis sobre la rama principal:

| Métrica | Valor |
| --- | --- |
| Líneas de código analizadas | 8 828 |
| Bugs | 0 |
| Vulnerabilidades | 0 |
| Security hotspots | 0 |
| Code smells | 0 |
| Deuda técnica (`sqale_index`) | 0 minutos |
| Duplicación de líneas | 4.3 % |

Estas cifras deben leerse con cautela. Corresponden al **análisis automático**
de SonarQube, cuyo conjunto de reglas para Swift es más limitado que el de un
análisis completo desde CI, y **no incluyen cobertura**. El análisis desde el
pipeline se configuró en esta fase precisamente para obtener métricas completas
y con cobertura asociada.

El único indicador con valor distinto de cero es la **duplicación del 4.3 %**,
concentrada en el código del lienzo, coherente con las reescrituras sucesivas
descritas en 2.2.

### 3.4 Seguridad

El escaneo con **OWASP ZAP** se configuró en
`.github/workflows/security-scan.yml` como *baseline* (pasivo) contra los
endpoints de Supabase, que constituyen la única superficie expuesta a internet
del proyecto: el binario de iOS no es analizable por ZAP.

Conviene precisar el alcance respecto a lo que pide la actividad. La búsqueda de
**inyección SQL** tiene un significado distinto en esta arquitectura: la
aplicación no construye sentencias SQL. El acceso a datos ocurre a través de
PostgREST con consultas parametrizadas y del cliente oficial de Supabase, y cada
tabla tiene Row Level Security activo. El riesgo de SQLi clásico es
estructuralmente bajo; el riesgo real está en las **políticas de autorización**,
que es donde se concentró el trabajo de esta fase.

Medidas de seguridad verificables en el repositorio:

- Row Level Security en todas las tablas de usuario, con políticas
  `user_id = auth.uid()`.
- `subscription_tier` protegido por un trigger que rechaza cualquier
  modificación que no provenga de `service_role`.
- Roles imposibles de auto-asignar por construcción: la tabla `user_roles` tiene
  RLS activo y únicamente políticas de `select` para `authenticated`, de modo
  que las operaciones de inserción, actualización y borrado sobre el propio rol
  se rechazan sin necesidad de una regla explícita.
- La función `admin_user_overview()` verifica el rol como primera instrucción y
  devuelve exclusivamente agregados: conteos y marcas de tiempo, nunca contenido
  de apuntes.
- La decodificación del rol en el cliente falla de forma cerrada: un token
  malformado, una reclamación ausente o un rol desconocido se resuelven como
  usuario común.

---

## 4. Lecciones aprendidas

**1. Una configuración de pruebas sin pruebas es peor que no tener ninguna.**
El plan de pruebas apuntaba a un target inexistente y deshabilitado. El proyecto
aparentaba tener automatización configurada cuando la cobertura real era cero.
Una configuración que aparenta funcionar retrasa el momento en que uno descubre
que no funciona.

**2. Medir cobertura sin definir el alcance produce una cifra inútil.**
La primera medición sobre el target completo dio 4.7 %. Exigir 80 % sobre ese
número habría obligado a escribir pruebas de interfaz de bajo valor únicamente
para satisfacer un umbral. Definir explícitamente qué módulos se miden
convirtió la métrica en algo accionable, y dejó el 4.7 % como dato honesto de
contexto en lugar de ocultarlo.

**3. Un código de salida cero no significa que algo haya funcionado.**
El trabajo de integración con SonarQube falló de forma silenciosa: el scanner
subía el reporte y terminaba con éxito aunque el servidor rechazara el análisis
por una clave de proyecto incorrecta. El job aparecía en verde mientras nada
llegaba al proyecto. Solo al consultar la API de SonarQube se detectó que el
último análisis seguía siendo uno anterior. Se corrigió añadiendo
`sonar.qualitygate.wait`, que obliga a esperar el procesamiento del servidor.

**4. Programar contra una API supuesta cuesta más que verificarla.**
Dos ejecuciones consecutivas del pipeline fallaron porque el script de cobertura
asumía la estructura de la salida de `xccov` en lugar de comprobarla. Al
descargar un `.xcresult` real y ejecutar el comando se vio que devuelve un
diccionario indexado por ruta, no una lista, y además que la consulta por
archivo tardaba minutos mientras que una sola consulta global tarda 1.4
segundos. Verificar antes habría evitado ambos errores.

**5. Las herramientas del entorno fallan en silencio.**
Una referencia de git corrupta —un archivo con un espacio en el nombre,
`First-Demo 2`, creado por el renombrado automático de macOS— dejó `git fetch`
roto durante tres meses. Durante ese tiempo el estado real del repositorio
remoto era desconocido, lo que llevó a conclusiones equivocadas sobre qué ramas
estaban integradas. Al repararlo aparecieron dos ramas distintas que difieren
únicamente en una mayúscula.

**6. Las restricciones de las herramientas gratuitas condicionan el flujo de
trabajo, no solo el presupuesto.** El plan gratuito de SonarQube Cloud analiza
la rama principal y los pull requests, pero no ramas de trabajo prolongadas. Eso
obliga a integrar mediante pull request para obtener métricas, lo cual resulta
ser una práctica mejor, pero fue impuesto por la herramienta y no por decisión
propia.

**7. Posponer una etapa es una decisión legítima siempre que se registre.**
El despliegue automático se pospuso deliberadamente hasta estabilizar
flashcards. La decisión es defendible; lo que no sería defendible es presentar
el pipeline como completo sin señalar que la etapa de entrega no existe.

---

## 5. Plan de mejora continua

### 5.1 Corto plazo (1 a 2 semanas)

| Acción | Resultado esperado |
| --- | --- |
| Añadir la etapa de despliegue automático a TestFlight mediante GitHub Actions y una API key de App Store Connect | Completar el ciclo CI/CD exigido por la actividad |
| Corregir el fallo de generación con 20 preguntas | El cuestionario largo falla actualmente con "la lista de preguntas llegó incompleta", probablemente por truncamiento de la respuesta del modelo |
| Ampliar la lista de archivos con cobertura exigida conforme se añadan pruebas | Que la cobertura crezca de forma sostenida en lugar de estancarse en los módulos actuales |
| Publicar los reportes de pruebas, seguridad y calidad dentro del repositorio | Los artefactos de CI caducan a los 14 días; la evidencia debe ser permanente |

### 5.2 Mediano plazo (1 a 2 meses)

| Acción | Resultado esperado |
| --- | --- |
| Extraer la lógica pura a un módulo o paquete Swift independiente | Permitir medir cobertura por target de forma significativa, sin listas de archivos |
| Añadir pruebas de integración para `SyncEngine` | Los dos defectos más costosos del proyecto fueron de sincronización y ninguno era detectable con pruebas unitarias |
| Definir una especificación OpenAPI de las edge functions y ejecutar `zap-api-scan` autenticado | Un escaneo pasivo sin autenticación apenas alcanza la superficie real de la API |
| Establecer un entorno de Supabase de pruebas separado del de producción | Hoy el escaneo de seguridad apunta al proyecto real |
| Automatizar la generación de este reporte de métricas en cada release | Reducir el trabajo manual de documentación |

### 5.3 Largo plazo

| Acción | Resultado esperado |
| --- | --- |
| Incorporar telemetría de errores en producción | Detectar defectos como el de sincronización sin depender de la observación manual |
| Generación incremental de flashcards por streaming | Eliminar la dependencia de una única respuesta completa del modelo y mejorar el tiempo de respuesta percibido |
| Predicción de temas débiles a partir del historial de respuestas | Sugerir repaso dirigido usando los datos que ya se almacenan en `flashcards_session` |
| Revisión periódica y documentada de políticas RLS | Que la autorización se verifique de forma regular y no solo cuando se añade una funcionalidad |
| Avanzar hacia CMMI nivel 3 | El nivel 2 planteado en la Actividad 4 ya cuenta con evidencia: control de versiones, CI, revisión por pull request y registro de cambios |

---

## 6. Evidencias

| Elemento | Ubicación |
| --- | --- |
| Código y pipeline | https://github.com/no-c-123/GirokIQ-iOS |
| Pull request de integración | https://github.com/no-c-123/GirokIQ-iOS/pull/1 |
| Definición del pipeline | `.github/workflows/ci.yml` |
| Escaneo de seguridad | `.github/workflows/security-scan.yml` |
| Configuración de SonarQube | `sonar-project.properties` |
| Alcance de la cobertura | `Scripts/coverage_targets.json` |
| Pruebas unitarias | `GirokIQ-iosTests/` |
| Diseño de roles | `Docs/Roles.md` |
| Migraciones de base de datos | `supabase/migrations/` |
| Reportes generados | `reports/` |
