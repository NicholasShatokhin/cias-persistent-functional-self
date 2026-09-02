# Оновлення рукопису після повного rerun — 2026-09-02

## Що змінилося науково

Рукопис повністю перераховано за новим end-to-end виконанням із канонічного публічного репозиторію. Старі числові результати не змішуються з новим запуском.

### 1. Основний causal-lesion результат відтворено

Confirmatory range: seeds 277–306, 30 seeds × 4 embodiment profiles × 3 conditions = 360 runs.

- Full composite continuity: **Q = 0.883**.
- Persistent-anchor lesion: **Q = 0.410**.
- Paired Full advantage: **+0.473**, 95% CI **[0.416, 0.531]**, Cohen's dz = **3.08**.
- Seed-level wins: **30/30**.
- Correct direction: **4/4 profiles**.
- Full lure capture: **0.035**.
- Lesion lure capture: **0.775**.
- Full lure-rejection advantage: **+0.740**, 95% CI **[0.653, 0.828]**, dz = **3.16**.

Висновок звужено до architecture-specific causal claim: persistent anchor є сильним причинним механізмом **усередині CIAS**.

### 2. Додано незалежний generic recurrent estimator

Окремі seed ranges:

- diagnostic fitting/CV: 315–326;
- technical preflight: 327–330;
- untouched held-out: 331–360.

Comparator не має explicit Self role, persistent lineage key або change-point reconnect rule. Він навчає Gaussian emission model лише на diagnostic lineage labels, а на test-time бачить той самий model-visible observation stream.

Held-out:

- CIAS Full identity continuity: **0.948**;
- generic recurrent estimator: **0.998**;
- paired Full-minus-generic: **−0.0506**, 95% CI **[−0.0676, −0.0345]**;
- CIAS Full lure capture: **0.023**;
- generic: **0.0017**;
- Full-minus-generic lure-rejection difference: **−0.0218**, 95% CI **[−0.0314, −0.0130]**.

Цей результат **відхиляє architectural uniqueness** explicit CIAS anchor для даного benchmark. Generic temporal state estimator може реалізувати еквівалентну функцію identity continuity неявно.

Важливе уточнення: CV вибрала нульовий **додатковий recurrent appearance-continuity penalty**, але current appearance components залишаються у diagnostic-fitted emission model. Тому стаття не стверджує, що appearance information узагалі непотрібна.

### 3. Додано mechanism-level parameter sensitivity

Окремий untouched range: seeds 361–390.

- 27 prespecified parameter settings;
- Full + anchor lesion;
- 4 profiles;
- **6480 runs**.

Обидва ефекти зберегли правильний знак, positive CI та direction ≥3/4 profiles у **25/27 settings (92.6%)**.

- median identity-continuity advantage: **+0.760**;
- median lure-rejection advantage: **+0.524**;
- worst lure-rejection advantage залишився positive: **+0.211**.

Дві конфігурації втратили identity advantage. Найінформативніша межа — завищення persistent reconnect gate до 0.77. Це підтримує **finite local robustness basin**, а не global parameter invariance.

### 4. History-reset висновок оновлено

Fresh confirmatory rerun більше не показує перевагу history reset за Q:

- Full Q = **0.883**;
- history-reset Q = **0.874**;
- Full-minus-reset = **+0.009**, 95% CI **[−0.005, 0.023]**.

Водночас:

- Full stage identity chain score = **1**;
- reset = **0**;
- Full initial identity retained at end = **1**;
- reset = **0**;
- whole-run fragmentation: Full **2.08**, reset **4.24**.

Отже final local re-identification і preservation of original cross-stage lineage є різними властивостями. Повна association history не потрібна для високого final-probe score, але цей score сам по собі не доводить збереження початкової lineage.

### 5. Progressive morphology order знову не підтримано

Matched diagnostic 261–272:

- progressive − final-from-start: +0.0147 [−0.0038, 0.0331];
- progressive − reverse: +0.0071 [−0.0041, 0.0183];
- progressive − random: +0.0051 [−0.0124, 0.0225].

Ця гіпотеза не входить у supported core theory.

## Як змінилися claims

Поточний supported claim:

> In the tested CIAS implementation, the explicit persistent causal identity anchor has a strong causal effect on lineage preservation under adversarial embodiment change. The benchmark itself does not require this explicit representation: a generic recurrent estimator can carry functionally equivalent cross-time state implicitly.

Рукопис більше не стверджує universal або cross-architecture necessity explicit Self anchor.

## Верстка і джерела

- Main manuscript: **9 IEEE pages**.
- Supplementary Material: **6 pages**.
- Нові figures: fresh confirmatory effects, embodiment consistency, independent estimator comparison, parameter-sensitivity basin.
- Старі confirmatory numbers 0.697/0.309 та 0.106/0.925 вилучені з актуального manuscript.
- Канонічний core SHA-256: `b81f43221b290fc09c06c69719a24533cdd802fe483347301d6015adda9eb38c`.
- Public repository: `https://github.com/NicholasShatokhin/cias-persistent-functional-self`.

