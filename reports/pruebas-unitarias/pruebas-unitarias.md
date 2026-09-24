# Reporte de pruebas unitarias — GirokIQ

**Resultado general:** Passed

| Métrica | Valor |
| --- | ---: |
| Pruebas ejecutadas | 89 |
| Aprobadas | 89 |
| Fallidas | 0 |
| Omitidas | 0 |

Generado con `Scripts/test_report.py` a partir del bundle `.xcresult`
producido por `xcodebuild test`.

## AIServiceErrorTests

4 de 4 pruebas aprobadas.

| Prueba | Resultado |
| --- | --- |
| API Errors Are Not Timeouts | ✅ Passed |
| Errors Carry A User Facing Description | ✅ Passed |
| Other URL Errors Are Not Timeouts | ✅ Passed |
| Recognises Timeout From URL Loading | ✅ Passed |

## AdminDailyMetricTests

6 de 6 pruebas aprobadas.

| Prueba | Resultado |
| --- | --- |
| A Malformed Date Throws | ✅ Passed |
| A Missing Date Throws | ✅ Passed |
| A Quiet Day Decodes As Zeros | ✅ Passed |
| Decodes A Postgres Date | ✅ Passed |
| Round Trips Through Codable | ✅ Passed |
| The Day Is Parsed In UTC Not Local Time | ✅ Passed |

## AdminPlatformStatsTests

9 de 9 pruebas aprobadas.

| Prueba | Resultado |
| --- | --- |
| Active Share Is Clamped To One | ✅ Passed |
| An Empty Platform Decodes As Zeros | ✅ Passed |
| Average Pages Per Notebook | ✅ Passed |
| Decodes A Complete Row | ✅ Passed |
| Null Aggregates Decode As Zeros | ✅ Passed |
| Pro Share Is The Fraction Of Paid Accounts | ✅ Passed |
| Shares Are Zero When There Are No Accounts | ✅ Passed |
| Storage Bytes Survives Values Beyond Int32 | ✅ Passed |
| Storage Label Is Human Readable | ✅ Passed |

## AdminUserOverviewRowTests

8 de 8 pruebas aprobadas.

| Prueba | Resultado |
| --- | --- |
| A Missing User Id Is A Hard Failure | ✅ Passed |
| An Account With No Activity Decodes | ✅ Passed |
| An Unknown Role Decodes As A Plain User | ✅ Passed |
| Decodes A Complete Row | ✅ Passed |
| Id Mirrors The User Id | ✅ Passed |
| Memberwise Initialiser Round Trips | ✅ Passed |
| Missing Counts Default To Zero | ✅ Passed |
| Rows Are Equatable And Hashable | ✅ Passed |

## AppUserRoleTests

16 de 16 pruebas aprobadas.

| Prueba | Resultado |
| --- | --- |
| Claim Key Matches The Database Hook | ✅ Passed |
| Decode Returns All Claims | ✅ Passed |
| Decode Returns Nil For A Structurally Invalid Token | ✅ Passed |
| Decodes A Payload That Needs Base64 Padding | ✅ Passed |
| Decodes Base64 URL Substitutions | ✅ Passed |
| Malformed Tokens Fall Back To User | ✅ Passed |
| Missing Claim Falls Back To User | ✅ Passed |
| Non String Claim Falls Back To User | ✅ Passed |
| Payload That Is AJSON Array Falls Back To User | ✅ Passed |
| Payload That Is Valid Base64 But Not JSON Falls Back To User | ✅ Passed |
| Raw Values Match The Postgres Enum | ✅ Passed |
| Reads The Admin Claim | ✅ Passed |
| Reads The User Claim | ✅ Passed |
| Role Survives Codable Round Trip | ✅ Passed |
| Titles Are Non Empty | ✅ Passed |
| Unknown Role Falls Back To User | ✅ Passed |

## FlashcardsGeneratorParsingTests

16 de 16 pruebas aprobadas.

| Prueba | Resultado |
| --- | --- |
| Accepts A Clean JSON Array | ✅ Passed |
| Accepts A Clean JSON Object | ✅ Passed |
| Does Not Drop Text That Merely Mentions Reading | ✅ Passed |
| Drops Model Apologies That Mean The Page Was Blank | ✅ Passed |
| Ignores Surrounding Whitespace And Newlines | ✅ Passed |
| Keeps Real Study Text | ✅ Passed |
| Preserves Original Casing And Punctuation Of Kept Text | ✅ Passed |
| Readable Text Is Empty Without Elements | ✅ Passed |
| Readable Text Joins Elements With A Blank Line | ✅ Passed |
| Readable Text Skips Empty And Whitespace Only Elements | ✅ Passed |
| Strips Conversational Prose Around The JSON | ✅ Passed |
| Throws On Empty Input | ✅ Passed |
| Throws When The Closing Brace Is Missing | ✅ Passed |
| Throws When There Is No JSON At All | ✅ Passed |
| Treats Empty Input As Empty | ✅ Passed |
| Unwraps A Markdown Fenced Code Block | ✅ Passed |

## FlashcardsModelsTests

16 de 16 pruebas aprobadas.

| Prueba | Resultado |
| --- | --- |
| Can Continue Only With At Least One Page Selected | ✅ Passed |
| Config Survives Codable Round Trip | ✅ Passed |
| Display Titles Are Non Empty | ✅ Passed |
| Elapsed Text Formats Minutes And Seconds | ✅ Passed |
| Estimated Minutes Never Drops Below One | ✅ Passed |
| Estimated Minutes Scales With Question Count And Mode | ✅ Passed |
| Incorrect Never Goes Negative | ✅ Passed |
| Missed Returns Only Incorrect Answers | ✅ Passed |
| Review Topics Dedupes Trims And Skips Blanks | ✅ Passed |
| Review Topics Is Empty For A Perfect Score | ✅ Passed |
| Score Percent Is Zero When Nothing Was Asked | ✅ Passed |
| Score Percent Truncates Toward Zero | ✅ Passed |
| Self Rating Maps Onto The SM2 Quality Scale | ✅ Passed |
| Setting Study Mode Writes Back Mode And Question Type | ✅ Passed |
| Study Mode Flattens Mode And Question Type | ✅ Passed |
| Study Mode Round Trips Through Every Case | ✅ Passed |

## SubscriptionTierTests

14 de 14 pruebas aprobadas.

| Prueba | Resultado |
| --- | --- |
| App State Decodes A Row From Supabase | ✅ Passed |
| App State Defaults Everything Optional To Nil | ✅ Passed |
| App State Encodes Snake Case Keys For Supabase | ✅ Passed |
| App State Id Mirrors The User Id | ✅ Passed |
| App State Survives A Codable Round Trip | ✅ Passed |
| Free Plan Is Capped At Three Notebooks | ✅ Passed |
| Persisted Defaults To Free When Nothing Is Stored | ✅ Passed |
| Persisted Falls Back To Free On An Unknown Value | ✅ Passed |
| Persisted Round Trips Both Tiers | ✅ Passed |
| Pro Plan Has No Notebook Cap | ✅ Passed |
| Raw Values Match The Database Contract | ✅ Passed |
| Storage Limit Label Is Human Readable | ✅ Passed |
| Storage Limits | ✅ Passed |
| Tier Survives Codable Round Trip | ✅ Passed |

