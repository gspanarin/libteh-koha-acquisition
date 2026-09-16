Koha/Plugin/Com/Library/Acquisition/
├── Acquisition.pm           # Головний PM-файл (хуки Koha, install/uninstall)
├── lib/
│   ├── DB.pm                      # Робота з БД (CRUD для libteh_*)
│   └── RTFParser.pm               # Генератор/підстановник змінних у RTF
│
└── intranet/                      # Шаблони для службового інтерфейсу
    ├── templates/
    │   ├── main.tt                # Головна сторінка плагіна
    │   ├── kso_in.tt              # КСО Надходження
    │   ├── kso_out.tt             # КСО Вибуття
    │   ├── kso_movement.tt        # КСО Рух фонду
    │   ├── fund_audit.tt          # Перевірка фонду (адаптивна для mobile)
    │   └── settings.tt            # Налаштування та RTF шаблони
    ├── css/
    └── js/                        # Скрипти сканера штрих-кодів, DataTables тощо






