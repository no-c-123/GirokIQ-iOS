# Análisis de seguridad — OWASP ZAP

**Objetivo del escaneo:** `https://bapqxqydqzopbpjrpnna.supabase.co`
**Tipo:** baseline (pasivo), sin autenticación
**Herramienta:** OWASP ZAP vía `zaproxy/action-baseline@v0.15.0`
**Ejecución:** https://github.com/no-c-123/GirokIQ-iOS/actions/runs/35963119773
**Fecha:** 24 de septiembre de 2026

Reportes completos en esta misma carpeta: `zap-baseline-report.html`,
`.md` y `.json`.

---

## 1. Por qué se escanea el backend y no la aplicación

ZAP es un escáner de aplicaciones web y APIs: trabaja sobre tráfico HTTP. Una
aplicación nativa de iOS no es analizable por ZAP, así que el objetivo del
escaneo es la única superficie de GirokIQ expuesta a internet: el proyecto de
Supabase, que agrupa la API REST (PostgREST), el servicio de autenticación y
las tres edge functions (`ai-chat`, `verify-subscription`, `delete-account`).

Se eligió deliberadamente el modo **pasivo**. El modo activo envía payloads de
ataque reales, y el objetivo es infraestructura gestionada por un tercero; un
escaneo activo recurrente contra Supabase sería inapropiado y podría
interpretarse como abuso del servicio.

---

## 2. Resultado

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

---

## 3. Interpretación de los hallazgos

**Las seis alertas se refieren a la misma cookie: `__cf_bm`.**

`__cf_bm` es la cookie de gestión de bots de Cloudflare, que opera como capa
previa a Supabase. No la establece el código de GirokIQ, no la lee la
aplicación y no contiene datos de sesión de usuario. Los atributos que ZAP
señala —`SameSite=None`, alcance `Domain=supabase.co`— los define Cloudflare, y
el proyecto no tiene forma de modificarlos.

La alerta *Timestamp Disclosure* corresponde a la marca de expiración de esa
misma cookie, un valor Unix en la cabecera `Set-Cookie`. Es el falso positivo
más común de ZAP.

*Non-Storable Content* señala respuestas con `no-store`, que para una API es el
comportamiento **correcto**, no un defecto.

**En consecuencia: el escaneo no encontró ninguna vulnerabilidad atribuible al
código del proyecto.**

---

## 4. Limitación del escaneo (importante)

El propio reporte contiene el dato que delimita su alcance:

| Estadística | Valor |
| --- | ---: |
| Endpoints alcanzados | 4 |
| Respuestas con código 4xx | 100 % |
| Respuestas con `application/json` | 100 % |

Los cuatro endpoints alcanzados fueron `/`, `/robots.txt`, `/favicon.ico` y la
raíz del dominio. **El escaneo nunca llegó a la API real.** La razón es que
PostgREST y las edge functions exigen la cabecera `apikey` y un token JWT
válido; sin credenciales, todo responde 401 y ZAP no puede recorrer nada.

Esto significa que **ausencia de hallazgos no equivale a ausencia de
vulnerabilidades**. Lo que este escaneo demuestra es que la API no expone
superficie a un visitante anónimo, lo cual es en sí mismo un resultado
positivo, pero no es una auditoría de la lógica de autorización.

Para cubrir esa brecha hay dos acciones en el plan de mejora del informe de
cierre: definir una especificación OpenAPI de las edge functions y ejecutar
`zap-api-scan` **autenticado**, y levantar un proyecto de Supabase de pruebas
para poder escanear de forma agresiva sin tocar producción.

---

## 5. Sobre XSS e inyección SQL

La actividad pide identificar vulnerabilidades como XSS o SQLi. Ambas merecen
una respuesta específica para esta arquitectura, y no un simple "no se
encontraron".

**Inyección SQL.** La aplicación no construye sentencias SQL en ningún punto.
El acceso a datos ocurre mediante PostgREST y el cliente oficial de Supabase,
que parametriza las consultas, y cada tabla tiene Row Level Security activo.
Las funciones SQL propias del proyecto (`increment_ai_usage_daily`,
`admin_user_overview`, `current_user_role`) no concatenan entrada del usuario:
reciben parámetros tipados o leen reclamaciones del JWT. Para una inyección
clásica no existe el punto de entrada habitual.

**XSS.** GirokIQ no renderiza HTML. Es una aplicación nativa de SwiftUI, y el
texto del usuario se dibuja en vistas nativas, no en un motor web. El vector
tradicional de XSS no aplica al cliente.

El riesgo real de esta arquitectura no es la inyección, sino la **autorización
mal configurada**: una política RLS demasiado permisiva expondría datos de
otros usuarios sin necesidad de ninguna inyección. Por eso el trabajo de esta
fase se concentró ahí, y por eso los roles se diseñaron de modo que la
auto-promoción sea imposible por construcción y no por una regla que alguien
pudiera olvidar.

Ese riesgo se verifica hoy con pruebas manuales y con la revisión de las
migraciones. Automatizarlo —una suite que intente leer datos de otro usuario y
compruebe que la base de datos los rechaza— es la mejora de seguridad más
valiosa pendiente, y está registrada en el plan de mejora continua.
