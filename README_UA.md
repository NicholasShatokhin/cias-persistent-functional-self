# Persistent Functional Self — пакет відтворення

Код, протоколи, скрипти аналізу та еталонні результати дослідження **A Causal Theory of Persistent Functional Self in Embodied Artificial Agents**.

Репозиторій призначений для незалежного використання. Після клонування достатньо вказати локальний Godot 4.7.x і запустити повну серію. Один завершений еталонний запуск збережено в `reference_results/`; runner ніколи не використовує ці файли як вхідні дані.

## Вимоги

- Windows 10/11 або Linux
- Python 3.10+
- Godot Engine **4.7.x**
- доступ до Інтернету під час першого запуску для встановлення пакетів із `requirements.txt`

## Швидкий запуск

Перевірка harness без відкриття confirmatory/held-out діапазонів:

```powershell
.\RUN_SMOKE_WINDOWS.bat "C:\path\to\Godot_v4.7-stable_win64.exe"
```

Повне відтворення:

```powershell
.\RUN_ALL_WINDOWS.bat "C:\path\to\Godot_v4.7-stable_win64.exe"
```

Linux:

```bash
./RUN_SMOKE_LINUX.sh /path/to/godot
./RUN_ALL_LINUX.sh /path/to/godot
```

Runner сам створює Python-середовище, перевіряє SHA канонічного ontology core, виконує всі етапи, обчислює статистику та записує provenance.

## Експериментальна програма

| Етап | Seeds | Призначення |
|---|---:|---|
| Initial diagnostic | 253–260 | Відтворення ceiling та unmatched-change-point проблем першого дизайну. |
| Matched diagnostic | 261–272 | Перевірка виправленого matched design і theory-reduction conditions. |
| Preflight | 273–276 | Структурні та nondegeneracy перевірки. |
| Confirmatory | 277–306 | Порівняння Full, lesion persistent anchor та history-reset control. |
| Generic-estimator diagnostic | 315–326 | Налаштування generic recurrent estimator лише на diagnostic labels. |
| Comparator preflight | 327–330 | Технічна перевірка frozen diagnostic-only estimator. |
| Independent-estimator held-out | 331–360 | Незалежне порівняння CIAS з generic estimator. |
| Parameter-sensitivity held-out | 361–390 | 27 заздалегідь визначених parameter settings на окремому held-out діапазоні. |

Seeds 307–314 у цьому пакеті навмисно не використовуються.

Повний опис: `protocols/COMPLETE_EXPERIMENTAL_PROGRAM.md`.

## Еталонний завершений запуск

`reference_results/` містить один завершений запуск на Godot `4.7.stable.official.5b4e0cb0f` з канонічним core, зазначеним у `provenance/FROZEN_CORE_IDENTITY.json`.

Основні результати:

- Full проти persistent-anchor lesion, перевага identity continuity: **0.4734**, 95% CI **[0.4160, 0.5308]**.
- Full проти persistent-anchor lesion, перевага lure rejection: **0.7405**, 95% CI **[0.6529, 0.8280]**.
- CIAS Full мінус generic recurrent estimator, continuity: **−0.0506**, 95% CI **[−0.0676, −0.0345]**.
- CIAS Full мінус generic recurrent estimator, lure rejection: **−0.0218**, 95% CI **[−0.0314, −0.0130]**.
- Знаки обох основних Full-vs-lesion ефектів збереглися у **25/27 (92.6%)** prespecified parameter settings за pointwise 95% bootstrap intervals.
- За одночасною family-wise max-bootstrap перевіркою всіх 54 sensitivity effects обидві нижні межі залишилися позитивними у **24/27 (88.9%)** settings.

Від’ємні значення CIAS-minus-generic означають, що generic recurrent estimator показав трохи вищий результат за цими двома held-out метриками. Сирі й похідні файли включені для прямої перевірки.

## Куди записується новий запуск

```text
experiments/paper_experiments/results/generated/
experiments/additional_experiments/results/generated/
provenance/paper_experiments_execution/
provenance/additional_experiments_execution/
provenance/EXECUTION_SUMMARY.json
```

Ці каталоги відокремлені від `reference_results/`.

## Продовження перерваного запуску

Перед першим виконанням кожного protected held-out range записується access marker. Якщо процес перервано після відкриття такого діапазону:

```powershell
.\RUN_RESUME_WINDOWS.bat "C:\path\to\Godot_v4.7-stable_win64.exe"
```

Resume зберігає вже завершені етапи й продовжує з checkpoint.

## Канонічний механізм

```text
frozen_code/ontology_core.gd
```

Його SHA-256 записано в `provenance/FROZEN_CORE_IDENTITY.json` і автоматично перевіряється перед запуском.


## GitHub, environment та архівація

Frame-level `parameter_sensitivity_tracking.csv` (~323 MB) зберігається як `parameter_sensitivity_tracking.csv.gz` (~7.5 MB), тому в репозиторії немає git objects >100 MB і Git LFS не потрібен. SHA-256 обох представлень записано в `reference_results/RAW_REFERENCE_FILE.json`.

Точні версії Python-пакетів еталонного запуску збережені в `reference_environment/requirements-reference.txt`; діапазони в `requirements.txt` залишені для майбутніх compatible reruns.

Повний повторний запуск заархівовано в Zenodo під DOI 10.5281/zenodo.22253924. Попередній DOI 10.5281/zenodo.22207678 залишається незмінним історичним знімком попередньої версії.

Ліцензування й citation metadata: `LICENSE` та `CITATION.cff`.
