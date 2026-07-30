import json
import yaml

from monk.config import Config

class Analyzer:
    def __init__(self, config: Config):
        self.config = config

    def diagnose(self):
        # Load the monk.yaml file
        with open('monk.yaml', 'r') as f:
            monk_yaml = yaml.safe_load(f)

        # Initialize a set to store the names of grouped runnables
        grouped_runnables = set()

        # Iterate over the stacks in the monk.yaml file
        for stack_name, stack_config in monk_yaml.get('stack', {}).items():
            # Check if the stack has a 'defines' key with value 'group'
            if stack_config.get('defines') == 'group':
                # Add the members of the group to the set of grouped runnables
                grouped_runnables.update(stack_config.get('members', []))

        # Initialize a list to store the diagnostics
        diagnostics = []

        # Iterate over the runnables in the monk.yaml file
        for runnable_name, runnable_config in monk_yaml.get('app', {}).items():
            # Check if the runnable is not in any group
            if runnable_name not in grouped_runnables:
                # Create a diagnostic for the ungrouped runnable
                diagnostic = {
                    'severity': 'info',
                    'message': f"'{runnable_name}' is not in any group and has no connections. Consider removing it if unused, or add to a group.",
                    'file': 'monk.yaml',
                    'line': 0,
                    'column': 0,
                    'source': 'structural',
                    'sourceLine': runnable_name
                }
                # Add the diagnostic to the list of diagnostics
                diagnostics.append(diagnostic)

        # Return the diagnostics
        return diagnostics

    def analyze(self):
        # Load the MANIFEST file
        with open('MANIFEST', 'r') as f:
            manifest = f.read().splitlines()

        # Initialize a set to store the names of loaded runnables
        loaded_runnables = set()

        # Iterate over the lines in the MANIFEST file
        for line in manifest:
            # Check if the line starts with 'IMAGE'
            if line.startswith('IMAGE'):
                # Extract the name of the runnable from the line
                runnable_name = line.split()[1].split(':')[0]
                # Add the name of the runnable to the set of loaded runnables
                loaded_runnables.add(runnable_name)

        # Initialize a list to store the diagnostics
        diagnostics = []

        # Iterate over the runnables in the monk.yaml file
        for runnable_name, runnable_config in self.config.get('app', {}).items():
            # Check if the runnable is not loaded
            if runnable_name not in loaded_runnables:
                # Create a diagnostic for the unloaded runnable
                diagnostic = {
                    'severity': 'info',
                    'message': f"'{runnable_name}' is not loaded and has no connections. Consider removing it if unused, or load it.",
                    'file': 'monk.yaml',
                    'line': 0,
                    'column': 0,
                    'source': 'structural',
                    'sourceLine': runnable_name
                }
                # Add the diagnostic to the list of diagnostics
                diagnostics.append(diagnostic)

        # Return the diagnostics
        return diagnostics
