#!/bin/bash
set -e

# Parse command line arguments
CLUSTER_MODE=""
CLUSTER_CONTEXT=""

usage() {
  cat << EOF
🎮 K8sQuest Installation

Usage: $0 [OPTIONS]

Options:
  --kind                    Create a new kind cluster (k8squest)
  --cluster-context NAME    Use an existing cluster context
  -h, --help               Show this help message

Examples:
  $0                                          # Interactive mode
  $0 --kind                                   # Create kind cluster
  $0 --cluster-context my-cluster            # Use existing context

EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --kind)
      CLUSTER_MODE="kind"
      shift
      ;;
    --cluster-context)
      CLUSTER_MODE="existing"
      CLUSTER_CONTEXT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "❌ Unknown option: $1"
      echo "Run '$0 --help' for usage information"
      exit 1
      ;;
  esac
done

echo "🎮 K8sQuest Installation"
echo "========================"
echo ""

# Check prerequisites
command -v kubectl >/dev/null || { echo "❌ kubectl not found. Install with: brew install kubectl"; exit 1; }
command -v python3 >/dev/null || { echo "❌ python3 not found"; exit 1; }

echo "✅ Prerequisites OK"
echo ""

# Create virtual environment if it doesn't exist
if [ ! -d "venv" ]; then
  echo "🐍 Creating Python virtual environment..."
  python3 -m venv venv
  if [ ! -d "venv" ]; then
    echo "❌ Failed to create virtual environment"
    exit 1
  fi
fi

# Activate virtual environment and install dependencies
echo "📦 Installing Python dependencies..."
if [ -f "venv/bin/activate" ]; then
  source venv/bin/activate
elif [ -f "venv/Scripts/activate" ]; then
  source venv/Scripts/activate
else
  echo "❌ Virtual environment activation script not found"
  echo "Expected: venv/bin/activate or venv/Scripts/activate"
  exit 1
fi
pip install -q -r requirements.txt

echo "✅ Python packages installed"
echo ""

# Cluster selection
if [ -z "$CLUSTER_MODE" ]; then
  # Interactive mode - no arguments provided
  echo "🎯 Cluster Selection"
  echo "===================="
  echo ""
  echo "Choose your cluster option:"
  echo "  1) Create a new kind cluster (k8squest) [default]"
  echo "  2) Use an existing cluster context"
  echo ""
  read -p "Enter your choice (1 or 2) [1]: " cluster_choice
  
  # Default to 1 if empty
  cluster_choice=${cluster_choice:-1}

  case $cluster_choice in
    1)
      CLUSTER_MODE="kind"
      ;;
    2)
      CLUSTER_MODE="existing"
      ;;
    *)
      echo "❌ Invalid choice. Please run the script again and select 1 or 2."
      exit 1
      ;;
  esac
fi

case $CLUSTER_MODE in
  kind)
    # Check if kind is installed, install if not
    if ! command -v kind >/dev/null; then
      echo "📦 kind not found. Installing kind..."
      if command -v brew >/dev/null; then
        brew install kind
        echo "✅ kind installed successfully"
      else
        echo "❌ Homebrew not found. Please install kind manually:"
        echo "   https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
        exit 1
      fi
    else
      echo "✅ kind is already installed"
    fi
    
    # Create Kubernetes cluster
    if ! kind get clusters | grep k8squest >/dev/null 2>&1; then
      echo "🔧 Creating Kubernetes cluster..."
      kind create cluster --name k8squest
    else
      echo "✅ Cluster already exists"
    fi
    
    kubectl config use-context kind-k8squest
    CLUSTER_CONTEXT="kind-k8squest"
    ;;
    
  existing)
    # If context not provided via CLI, ask interactively
    if [ -z "$CLUSTER_CONTEXT" ]; then
      # List available contexts
      echo ""
      echo "Available cluster contexts:"
      echo "============================"
      kubectl config get-contexts -o name | nl -w2 -s') '
      echo ""
      
      # Get list of contexts into an array (bash 3.2 compatible)
      contexts=()
      while IFS= read -r line; do
        contexts+=("$line")
      done < <(kubectl config get-contexts -o name)
      
      if [ ${#contexts[@]} -eq 0 ]; then
        echo "❌ No cluster contexts found in KUBECONFIG"
        exit 1
      fi
      
      read -p "Enter the number or name of the context to use: " context_choice
      
      # Check if input is a number
      if [[ "$context_choice" =~ ^[0-9]+$ ]]; then
        # Convert to 0-based index
        index=$((context_choice - 1))
        if [ $index -ge 0 ] && [ $index -lt ${#contexts[@]} ]; then
          CLUSTER_CONTEXT="${contexts[$index]}"
        else
          echo "❌ Invalid selection"
          exit 1
        fi
      else
        # Assume it's a context name
        CLUSTER_CONTEXT="$context_choice"
      fi
    fi
    
    # Verify the context exists
    if ! kubectl config get-contexts -o name | grep -q "^${CLUSTER_CONTEXT}$"; then
      echo "❌ Context '${CLUSTER_CONTEXT}' not found"
      exit 1
    fi
    
    echo "✅ Using context: ${CLUSTER_CONTEXT}"
    kubectl config use-context "${CLUSTER_CONTEXT}"
    ;;
    
  *)
    echo "❌ Invalid cluster mode"
    exit 1
    ;;
esac

echo ""

# Create k8squest namespace
echo "🏗️  Setting up k8squest namespace..."
kubectl create namespace k8squest --dry-run=client -o yaml | kubectl apply -f -

# Setup RBAC for safety
echo "🛡️  Configuring safety guards (RBAC)..."
if [ -f "rbac/k8squest-rbac.yaml" ]; then
  kubectl apply -f rbac/k8squest-rbac.yaml
  echo "✅ Safety guards configured"
else
  echo "⚠️  Warning: RBAC config not found, skipping"
fi

echo ""
echo "🚀 Setup Complete!"
echo ""
echo "To start playing, use the shortcut:"
echo "  ./play.sh"
echo ""
