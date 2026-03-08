#!/bin/bash

# If not already a git repo
git init
git add .
git commit -m "Initial project commit"

# Connect to GitHub
git remote add origin git@github.com:tolik505/fd-monitor.git

# Ensure branch name matches remote (GitHub defaults to main)
git branch -M main

# This is the key command
git pull origin main --allow-unrelated-histories

# Resolve any conflicts if they appear, then:
git push -u origin main
