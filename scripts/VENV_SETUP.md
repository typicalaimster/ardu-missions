# Virtual Environment Setup Guide

## What is a Virtual Environment?

A Python virtual environment (venv) is an isolated Python environment that allows you to install packages without affecting your system Python installation. Think of it as a dedicated workspace for your project.

## Why Use Virtual Environments?

1. **Isolation** - Each project has its own dependencies, preventing conflicts
2. **Reproducibility** - Easy to share exact package versions with other developers
3. **Clean** - Uninstall entire environment by just deleting a folder
4. **Best Practice** - Industry standard for Python projects

## Quick Start

### Linux/Mac

```bash
# Navigate to scripts directory
cd /home/coder/ardu-missions/scripts/

# Create virtual environment (one-time setup)
python3 -m venv .venv

# Activate virtual environment (do this every time you start work)
source .venv/bin/activate

# Your prompt will change to show (.venv) prefix:
# (.venv) user@host:~/ardu-missions/scripts$

# Install dependencies (if any)
pip install -r requirements.txt

# Run scripts
python3 analyze_flight_logs.py ../logs/*.kmz

# Deactivate when done
deactivate
```

### Windows PowerShell

```powershell
# Navigate to scripts directory
cd C:\Users\YourName\ardu-missions\scripts\

# Create virtual environment (one-time setup)
python -m venv .venv

# Activate virtual environment
.venv\Scripts\Activate.ps1

# If you get execution policy error, run this first:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Your prompt will change to show (.venv) prefix

# Install dependencies (if any)
pip install -r requirements.txt

# Run scripts
python analyze_flight_logs.py ..\logs\*.kmz

# Deactivate when done
deactivate
```

### Windows Command Prompt

```cmd
cd C:\Users\YourName\ardu-missions\scripts\
python -m venv .venv
.venv\Scripts\activate.bat
pip install -r requirements.txt
python analyze_flight_logs.py ..\logs\*.kmz
deactivate
```

## Daily Workflow

```bash
# Start of work session
cd ardu-missions/scripts/
source .venv/bin/activate  # or .venv\Scripts\activate on Windows

# Do your work
python3 analyze_flight_logs.py ../logs/flight.kmz

# End of work session
deactivate
```

## Managing Dependencies

### Install a new package
```bash
# Make sure venv is activated!
pip install matplotlib

# Save to requirements.txt
pip freeze > requirements.txt
```

### Install all dependencies from requirements.txt
```bash
pip install -r requirements.txt
```

### List installed packages
```bash
pip list
```

### Upgrade a package
```bash
pip install --upgrade matplotlib
```

## Troubleshooting

### "python3: command not found" (Linux/Mac)
Try `python` instead of `python3`:
```bash
python -m venv .venv
```

### Virtual environment not activating (Windows)
If you get a permission error:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### "pip: command not found"
Make sure virtual environment is activated. If still not working:
```bash
python -m pip install -r requirements.txt
```

### How do I know if venv is activated?
Your prompt will show `(.venv)` prefix:
```bash
# Not activated:
user@host:~/scripts$

# Activated:
(.venv) user@host:~/scripts$
```

### Deleting/recreating virtual environment
```bash
# Deactivate if active
deactivate

# Delete the directory
rm -rf .venv  # Linux/Mac
# or
rmdir /s .venv  # Windows

# Create fresh environment
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## IDE Integration

### VS Code
VS Code auto-detects virtual environments. Select interpreter:
1. Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on Mac)
2. Type "Python: Select Interpreter"
3. Choose `.venv/bin/python` (or `.venv\Scripts\python.exe` on Windows)

### Cursor
Same as VS Code - Cursor is built on VS Code.

### PyCharm
PyCharm automatically detects and uses the virtual environment in your project folder.

## .gitignore Entry

The `.venv` directory should NOT be committed to git. Make sure your `.gitignore` includes:

```
# Python virtual environments
.venv/
venv/
env/
ENV/
```

## Alternative: System-wide Installation (Not Recommended)

If you really don't want to use venv (not recommended for development):

```bash
# Linux/Mac (may need sudo)
pip3 install matplotlib pandas

# But remember: this affects your entire system!
```

## Summary

```bash
# One-time setup
python3 -m venv .venv

# Every work session
source .venv/bin/activate    # Linux/Mac
.venv\Scripts\activate       # Windows

# Install packages as needed
pip install package_name

# Save dependencies
pip freeze > requirements.txt

# End session
deactivate
```

## Resources

- [Official Python venv documentation](https://docs.python.org/3/library/venv.html)
- [Real Python: Virtual Environments Primer](https://realpython.com/python-virtual-environments-a-primer/)
