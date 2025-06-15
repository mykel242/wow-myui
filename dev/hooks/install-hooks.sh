#!/bin/bash
# dev/hooks/install-hooks.sh
# Script to install Git hooks from the dev/hooks/ directory

echo "Installing Git hooks..."

# Check if we're in a git repository
if [ ! -d ".git" ]; then
    echo "Error: Not in a Git repository. Run this from the root of your repo."
    exit 1
fi

# Create hooks directory if it doesn't exist
mkdir -p .git/hooks

# Copy and install pre-commit hook
if [ -f "dev/hooks/pre-commit" ]; then
    cp dev/hooks/pre-commit .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    echo "✓ pre-commit hook installed"
else
    echo "✗ dev/hooks/pre-commit not found"
fi

# You can add more hooks here in the future
# if [ -f "hooks/post-commit" ]; then
#     cp hooks/post-commit .git/hooks/post-commit
#     chmod +x .git/hooks/post-commit
#     echo "✓ post-commit hook installed"
# fi

echo "Git hooks installation complete!"
echo ""
echo "To test the pre-commit hook:"
echo "  git add ."
echo "  git commit -m 'test version update'"
