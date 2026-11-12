# Pressure

Minimal macOS menu bar app that shows:

- current CPU load as a percentage
- current memory load as a percentage
- current disk usage of the primary internal drive as a percentage
- CPU temperature in degrees Fahrenheit and CPU performance limit as a percentage of max
- system thermal state via the thermometer icon

Temperature and performance-limit readings use platform-specific sensors on Intel and Apple silicon. Unavailable readings appear as `--`.

## Build

```sh
make
```

## Run

```sh
make run
```

## Stop

```sh
make kill
```

Click the menu bar item for:

- `Open Activity Monitor`
- `Open at Login`
- `Quit`
