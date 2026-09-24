# Análisis de calidad — SonarQube Cloud

**Proyecto:** `no-c-123_GirokIQ-iOS`
**Organización:** `no-c-123`
**Panel:** https://sonarcloud.io/dashboard?id=no-c-123_GirokIQ-iOS
**Análisis documentado:** pull request #1, septiembre de 2026

El análisis se ejecuta desde el pipeline (`.github/workflows/ci.yml`, job
`SonarQube Cloud analysis`) y no mediante el análisis automático de SonarQube,
porque el análisis automático **no puede importar reportes de cobertura**. La
cobertura que se envía proviene del mismo bundle `.xcresult` que usa el umbral
de CI, de modo que ambas cifras son consistentes por construcción.

---

## 1. Métricas del análisis

| Métrica | Valor |
| --- | ---: |
| Líneas de código analizadas (`ncloc`) | 25 698 |
| Bugs | 3 |
| Vulnerabilidades | 1 |
| Code smells | 0 |
| Security hotspots | 0 |
| Deuda técnica (`sqale_index`) | 0 min |
| Duplicación de líneas | 2.9 % |
| Cobertura (todo el proyecto) | 4.2 % |

### Nota sobre la deuda técnica

El `sqale_index` en cero merece explicación, porque un valor así suele indicar
que algo no se midió. En este caso corresponde a que no se reportaron code
smells: la deuda técnica de SonarQube se calcula como el tiempo estimado de
remediación de los smells, y sin smells el índice es cero. Los cuatro hallazgos
reportados se clasifican como bugs y vulnerabilidad, categorías que no
alimentan ese índice.

Esto **no** significa que el proyecto no tenga deuda técnica. El informe de
cierre documenta deuda real que SonarQube no captura con sus reglas por
defecto: la cobertura baja del target completo, la ausencia de pruebas de
integración para la sincronización y la duplicación acumulada en el código del
lienzo tras varias reescrituras.

### Nota sobre la cobertura

El 4.2 % corresponde a **todo el código** del proyecto. La cifra de 97.5 % que
reporta el pipeline corresponde a los módulos declarados en
`Scripts/coverage_targets.json`. Ambas son correctas y miden cosas distintas;
la explicación completa está en `Docs/Informe-de-cierre.md`, sección 3.1.

---

## 2. Quality gate

Resultado: **ERROR**

| Condición | Valor real | Umbral | Estado |
| --- | ---: | ---: | --- |
| `new_coverage` | 3.4 % | ≥ 80 % | ❌ |
| `new_reliability_rating` | 3 (C) | 1 (A) | ❌ |
| `new_security_rating` | 3 (C) | 1 (A) | ❌ |
| `new_maintainability_rating` | 1 (A) | 1 (A) | ✅ |
| `new_duplicated_lines_density` | 2.5 % | ≤ 3 % | ✅ |
| `new_security_hotspots_reviewed` | 100 % | 100 % | ✅ |

El quality gate aplica sobre **código nuevo**. Como este fue el primer análisis
del proyecto desde CI, SonarQube considera nuevas las 24 122 líneas del pull
request, es decir, prácticamente todo el código base. Por eso `new_coverage`
reporta 3.4 %: no mide la cobertura del código escrito en esta fase, sino la de
todo el proyecto.

Las condiciones de fiabilidad y seguridad fallaron por los cuatro hallazgos de
la sección 3, que ya fueron corregidos. En análisis posteriores, "código nuevo"
volverá a significar únicamente lo que cambie en cada pull request, y las
cifras serán representativas.

---

## 3. Hallazgos y su resolución

### 3.1 Vulnerabilidad — llavero sin control de acceso

| | |
| --- | --- |
| Regla | `swift:S6288` |
| Severidad | MAJOR |
| Ubicación | `GirokIQ-ios/Features/Auth/AuthViewModel.swift:580` |
| Mensaje | "This keychain item will not require authentication to be used" |

La clase `KeychainService` escribía elementos en el llavero sin especificar
`kSecAttrAccessible` ni control de acceso.

**Resolución: se eliminó la clase completa.** Al revisar el hallazgo se
descubrió que `KeychainService` era **código muerto**: su único uso era su
propia declaración. El comentario que la acompañaba, "still used by AIService",
estaba obsoleto, ya que las claves de API se movieron a la edge function
`ai-chat` y `AIService.hasAPIKey` hoy devuelve `true` de forma fija.

Endurecer los atributos del llavero habría sido corregir código que nadie
ejecuta. Eliminarlo resuelve la vulnerabilidad y elimina a la vez la superficie
de ataque y el código sin uso.

### 3.2 Bug — condicional sobre una promesa

| | |
| --- | --- |
| Regla | `typescript:S6544` |
| Severidad | MAJOR |
| Ubicación | `supabase/functions/verify-subscription/index.ts:20` |
| Mensaje | "Expected non-Promise value in a boolean conditional" |

`if (appleRootCertsPromise) return appleRootCertsPromise;`

La regla existe porque una prueba de veracidad sobre una promesa suele indicar
un `await` olvidado. Aquí el comportamiento era correcto: se trata de una
memoización deliberada que devuelve la promesa en vuelo para no descargar dos
veces los certificados raíz de Apple.

**Resolución:** se hizo explícita la intención con `!== null` y un comentario
que documenta por qué la comprobación es sobre la promesa y no sobre su valor
resuelto. El comportamiento no cambia; lo que cambia es que ahora se distingue
de un error.

### 3.3 y 3.4 Bugs — condicional con el mismo resultado en ambas ramas

| | |
| --- | --- |
| Regla | `swift:S3923` |
| Severidad | MAJOR |
| Ubicaciones | `GirokIQ-ios/Features/Home/HomeView.swift:2104`, `GirokIQ-ios/Features/Home/NewNotebookSheet.swift:41` |

Dos expresiones ternarias devolvían el mismo valor en ambas ramas:

- `.safeAreaPadding(.top, isPersistent ? GSpacing.md : GSpacing.md)`
- `colorScheme == .dark ? .gTextSecondary : .gTextSecondary`

Restos de condicionales que en algún momento tuvieron valores distintos y
quedaron igualados al ajustar el diseño. No provocan un fallo visible, pero
sugieren una intención que el código ya no cumple: quien lo lea asumirá que el
espaciado o el color cambian según el contexto, y no es así.

**Resolución:** se eliminó la condición en ambos casos. En el segundo se añadió
un comentario indicando que `gTextSecondary` ya es un token adaptable, que es
la razón por la que no necesita ramas.

---

## 4. Verificación posterior

Las 74 pruebas unitarias siguen aprobando después de las cuatro correcciones,
incluida la eliminación de `KeychainService`.

El siguiente análisis del pull request debe reportar 0 bugs y 0
vulnerabilidades. Las condiciones del quality gate relacionadas con cobertura
de código nuevo seguirán fallando mientras SonarQube considere todo el
proyecto como código nuevo.
