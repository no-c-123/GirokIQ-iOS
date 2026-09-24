# Reportes

Copias permanentes de la evidencia de pruebas, cobertura, calidad y seguridad.

Existen porque los artefactos que genera GitHub Actions **caducan a los 14
días** (`retention-days: 14` en `.github/workflows/ci.yml`), y la evidencia de
la entrega tiene que sobrevivir a ese plazo.

## Contenido

| Carpeta | Qué contiene | Cómo se genera |
| --- | --- | --- |
| `pruebas-unitarias/` | Resultado de las 74 pruebas, por suite | `Scripts/test_report.py <bundle>.xcresult <salida>.md` |
| `cobertura/` | Cobertura por archivo y reporte en formato genérico de SonarQube | `Scripts/coverage_report.py <bundle>.xcresult --markdown-out … --sonar-out …` |
| `calidad/` | Métricas de SonarQube Cloud | Se consultan a la API tras el análisis del pipeline |
| `seguridad/` | Reporte del escaneo OWASP ZAP | Artefacto del workflow `security-scan.yml` |

## Reproducir los reportes

```bash
# 1. Ejecutar las pruebas generando un bundle de resultados
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project GirokIQ-ios.xcodeproj \
  -scheme GirokIQ-ios \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  -resultBundlePath TestResults.xcresult

# 2. Generar los reportes a partir del bundle
python3 Scripts/test_report.py TestResults.xcresult reports/pruebas-unitarias/pruebas-unitarias.md
python3 Scripts/coverage_report.py TestResults.xcresult \
  --markdown-out reports/cobertura/cobertura.md \
  --sonar-out reports/cobertura/coverage-sonar.xml
```

## Nota sobre la cobertura

La cifra principal (97.5 %) corresponde a los **módulos bajo prueba**,
declarados explícitamente en `Scripts/coverage_targets.json`. La cobertura del
target completo (4.7 %) se reporta en el mismo documento como contexto.

Xcode mide cobertura por target, y GirokIQ es un único target de SwiftUI cuyas
vistas no son verificables con pruebas unitarias; exigir un 80 % sobre el target
completo mediría cuánta interfaz existe, no qué tan bien está probada la lógica.
El detalle de esta decisión está en `Docs/Informe-de-cierre.md`, sección 3.1.
