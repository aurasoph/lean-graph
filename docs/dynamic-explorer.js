// Interactive Mathlib Dependency Explorer
class DependencyExplorer {
    constructor() {
        this.graphData = null;
        this.allNodes = new Map();
        this.allLinks = new Map();
        this.visibleNodes = new Set();
        this.visibleLinks = new Set();
        this.nodePositions = new Map();
        
        this.currentGraph = 'structures';
        this.currentMode = 'search';
        this.activeNode = null;
        
        this.svg = null;
        this.simulation = null;
        this.container = null;
        this.zoom = null;
        
        this.initializeUI();
        this.loadGraph(this.currentGraph);
    }
    
    initializeUI() {
        // Set up search input
        const searchInput = document.querySelector('.search-input');
        const suggestions = document.querySelector('.suggestions');
        
        searchInput.addEventListener('input', (e) => {
            this.handleSearch(e.target.value, suggestions);
        });
        
        searchInput.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' && e.target.value.trim()) {
                this.addNodeByName(e.target.value.trim());
                e.target.value = '';
                suggestions.style.display = 'none';
            }
        });
        
        // Set up graph selector buttons
        document.querySelectorAll('.graph-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                document.querySelectorAll('.graph-btn').forEach(b => b.classList.remove('active'));
                e.target.classList.add('active');
                const graphType = e.target.dataset.graph;
                this.loadGraph(graphType);
            });
        });
        
        // Set up mode selector buttons
        document.querySelectorAll('.mode-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                document.querySelectorAll('.mode-btn').forEach(b => b.classList.remove('active'));
                e.target.classList.add('active');
                this.currentMode = e.target.dataset.mode;
                this.updateModeDisplay();
            });
        });
        
        // Set up control buttons
        document.querySelectorAll('[data-action]').forEach(btn => {
            btn.addEventListener('click', (e) => {
                this.handleAction(e.target.dataset.action);
            });
        });
        
        // Initialize SVG
        this.svg = d3.select('.graph-container svg');
        this.container = this.svg.append('g');
        
        // Setup zoom
        this.zoom = d3.zoom()
            .scaleExtent([0.1, 4])
            .on('zoom', (event) => {
                this.container.attr('transform', event.transform);
            });
        
        this.svg.call(this.zoom);
        
        // Add arrow marker
        this.svg.append('defs').append('marker')
            .attr('id', 'arrowhead')
            .attr('viewBox', '-0 -5 10 10')
            .attr('refX', 13)
            .attr('refY', 0)
            .attr('orient', 'auto')
            .append('path')
            .attr('d', 'M 0,-5 L 10 ,0 L 0,5')
            .attr('fill', '#999')
            .style('stroke', 'none');
    }
    
    async loadGraph(graphType) {
        this.currentGraph = graphType;
        
        try {
            document.querySelector('.loading').style.display = 'block';
            
            // Map graph types to actual file names  
            const fileMap = {
                'structures': 'mathlib_structures.dot',
                'imports': 'mathlib_imports.dot', 
                'type-deps': 'mathlib_type_deps.dot',
                'proof-deps': 'mathlib_proof_deps.dot'
            };
            
            const fileName = fileMap[graphType];
            if (!fileName) {
                throw new Error(`Unknown graph type: ${graphType}`);
            }
            
            // Load from GitHub raw content since GitHub Pages can't access large files
            const dotFile = `https://raw.githubusercontent.com/aurasoph/lean-graph/main/mathlib_graphs/${fileName}`;
            const response = await fetch(dotFile);
            
            if (!response.ok) {
                throw new Error(`Failed to load ${graphType} graph: ${response.status}`);
            }
            
            const dotContent = await response.text();
            this.graphData = this.parseDotFile(dotContent);
            
            this.allNodes.clear();
            this.allLinks.clear();
            this.visibleNodes.clear();
            this.visibleLinks.clear();
            
            // Process nodes and links
            this.graphData.nodes.forEach(node => {
                this.allNodes.set(node.id, node);
            });
            
            this.graphData.links.forEach(link => {
                const linkId = `${link.source}->${link.target}`;
                this.allLinks.set(linkId, link);
            });
            
            this.clearVisualization();
            document.querySelector('.loading').style.display = 'none';
            
            console.log(`Loaded ${this.allNodes.size} nodes and ${this.allLinks.size} links for ${graphType}`);
            
        } catch (error) {
            console.error('Error loading graph:', error);
            document.querySelector('.loading').innerHTML = 
                `<div class="error">Failed to load ${graphType} graph: ${error.message}<br>Make sure mathlib graphs are generated and available.</div>`;
        }
    }
    
    parseDotFile(dotContent) {
        const nodes = [];
        const links = [];
        const nodeMap = new Map();
        
        // Extract nodes and edges from DOT format
        const lines = dotContent.split('\n');
        let inGraph = false;
        
        for (const line of lines) {
            const trimmed = line.trim();
            
            if (trimmed.includes('digraph') || trimmed.includes('{')) {
                inGraph = true;
                continue;
            }
            
            if (trimmed === '}') {
                inGraph = false;
                break;
            }
            
            if (!inGraph) continue;
            
            // Parse edges: "source" -> "target"
            const edgeMatch = trimmed.match(/"([^"]+)"\s*->\s*"([^"]+)"/);
            if (edgeMatch) {
                const [, source, target] = edgeMatch;
                
                // Add nodes if not seen before
                if (!nodeMap.has(source)) {
                    const node = { id: source, name: source };
                    nodes.push(node);
                    nodeMap.set(source, node);
                }
                if (!nodeMap.has(target)) {
                    const node = { id: target, name: target };
                    nodes.push(node);
                    nodeMap.set(target, node);
                }
                
                links.push({ source: source, target: target });
            }
        }
        
        return { nodes, links };
    }
    
    handleSearch(query, suggestionsEl) {
        if (!query || !this.allNodes.size) {
            suggestionsEl.style.display = 'none';
            return;
        }
        
        const matches = Array.from(this.allNodes.keys())
            .filter(name => name.toLowerCase().includes(query.toLowerCase()))
            .slice(0, 10);
        
        if (matches.length === 0) {
            suggestionsEl.style.display = 'none';
            return;
        }
        
        suggestionsEl.innerHTML = matches
            .map(name => `<div class="suggestion-item" data-name="${name}">${name}</div>`)
            .join('');
        
        suggestionsEl.style.display = 'block';
        
        // Add click handlers to suggestions
        suggestionsEl.querySelectorAll('.suggestion-item').forEach(item => {
            item.addEventListener('click', () => {
                this.addNodeByName(item.dataset.name);
                suggestionsEl.style.display = 'none';
                document.querySelector('.search-input').value = '';
            });
        });
    }
    
    addNodeByName(nodeName) {
        if (!this.allNodes.has(nodeName)) {
            console.warn(`Node ${nodeName} not found`);
            return;
        }
        
        if (this.currentMode === 'traversal') {
            this.setActiveNode(nodeName);
        } else {
            this.addNodeToVisualization(nodeName);
        }
        
        this.updateVisualization();
    }
    
    addNodeToVisualization(nodeName) {
        if (this.visibleNodes.has(nodeName)) return;
        
        this.visibleNodes.add(nodeName);
        console.log(`Added node: ${nodeName}`);
    }
    
    setActiveNode(nodeName) {
        this.activeNode = nodeName;
        this.visibleNodes.clear();
        this.visibleLinks.clear();
        
        // Add the active node
        this.visibleNodes.add(nodeName);
        
        // Add all neighbors (k=1)
        this.allLinks.forEach((link, linkId) => {
            if (link.source === nodeName) {
                this.visibleNodes.add(link.target);
                this.visibleLinks.add(linkId);
            }
            if (link.target === nodeName) {
                this.visibleNodes.add(link.source);
                this.visibleLinks.add(linkId);
            }
        });
        
        this.updateActiveNodeDisplay();
    }
    
    updateActiveNodeDisplay() {
        const display = document.getElementById('active-node-display');
        if (display) {
            display.textContent = `Active: ${this.activeNode || 'None'}`;
        }
    }
    
    updateModeDisplay() {
        const searchControls = document.getElementById('search-controls');
        const traversalControls = document.getElementById('traversal-controls');
        const modeInfo = document.getElementById('mode-info');
        
        if (this.currentMode === 'search') {
            searchControls.style.display = 'block';
            traversalControls.style.display = 'none';
            modeInfo.textContent = 'Click to build custom neighborhoods';
        } else {
            searchControls.style.display = 'none';
            traversalControls.style.display = 'block';
            modeInfo.textContent = 'Shows k=1 neighbors of active node';
        }
    }
    
    handleAction(action) {
        switch (action) {
            case 'expand-parents':
                this.expandParents();
                break;
            case 'expand-children':
                this.expandChildren();
                break;
            case 'center-view':
                this.centerView();
                break;
            case 'clear':
                this.clearVisualization();
                break;
        }
    }
    
    expandParents() {
        const newNodes = new Set();
        
        this.visibleNodes.forEach(nodeName => {
            this.allLinks.forEach(link => {
                if (link.target === nodeName && !this.visibleNodes.has(link.source)) {
                    newNodes.add(link.source);
                }
            });
        });
        
        newNodes.forEach(node => this.visibleNodes.add(node));
        this.updateVisualization();
    }
    
    expandChildren() {
        const newNodes = new Set();
        
        this.visibleNodes.forEach(nodeName => {
            this.allLinks.forEach(link => {
                if (link.source === nodeName && !this.visibleNodes.has(link.target)) {
                    newNodes.add(link.target);
                }
            });
        });
        
        newNodes.forEach(node => this.visibleNodes.add(node));
        this.updateVisualization();
    }
    
    centerView() {
        if (this.simulation) {
            this.svg.transition().duration(750).call(
                this.zoom.transform,
                d3.zoomIdentity
            );
        }
    }
    
    clearVisualization() {
        this.visibleNodes.clear();
        this.visibleLinks.clear();
        this.activeNode = null;
        this.updateActiveNodeDisplay();
        this.updateVisualization();
    }
    
    updateVisualization() {
        if (!this.allNodes.size) return;
        
        // Determine visible links
        this.visibleLinks.clear();
        this.allLinks.forEach((link, linkId) => {
            if (this.visibleNodes.has(link.source) && this.visibleNodes.has(link.target)) {
                this.visibleLinks.add(linkId);
            }
        });
        
        // Prepare data for D3
        const nodes = Array.from(this.visibleNodes).map(id => ({
            id,
            name: id,
            fx: this.nodePositions.has(id) ? this.nodePositions.get(id).x : undefined,
            fy: this.nodePositions.has(id) ? this.nodePositions.get(id).y : undefined
        }));
        
        const links = Array.from(this.visibleLinks).map(linkId => {
            const link = this.allLinks.get(linkId);
            return {
                source: link.source,
                target: link.target
            };
        });
        
        // Update D3 visualization
        this.renderVisualization(nodes, links);
        
        // Update stats
        document.getElementById('graph-stats').textContent = 
            `${nodes.length} nodes, ${links.length} edges`;
    }
    
    renderVisualization(nodes, links) {
        // Clear previous simulation
        if (this.simulation) {
            this.simulation.stop();
        }
        
        // Setup new simulation
        this.simulation = d3.forceSimulation(nodes)
            .force('link', d3.forceLink(links).id(d => d.id).distance(80))
            .force('charge', d3.forceManyBody().strength(-200))
            .force('center', d3.forceCenter(400, 300))
            .force('collision', d3.forceCollide().radius(25));
        
        // Update links
        const link = this.container
            .selectAll('.link')
            .data(links, d => `${d.source.id || d.source}-${d.target.id || d.target}`);
        
        link.exit().remove();
        
        link.enter()
            .append('line')
            .attr('class', 'link')
            .merge(link);
        
        // Update nodes
        const node = this.container
            .selectAll('.node-group')
            .data(nodes, d => d.id);
        
        node.exit().remove();
        
        const nodeEnter = node.enter()
            .append('g')
            .attr('class', 'node-group')
            .call(this.createDrag());
        
        nodeEnter.append('circle')
            .attr('class', d => {
                let classes = 'node';
                if (d.id === this.activeNode) classes += ' active';
                return classes;
            })
            .attr('r', 8)
            .on('click', (event, d) => {
                this.handleNodeClick(d.id);
            });
        
        nodeEnter.append('text')
            .attr('class', 'node-label')
            .attr('dy', -12)
            .text(d => d.name.length > 20 ? d.name.substring(0, 20) + '...' : d.name);
        
        // Update existing nodes
        this.container.selectAll('.node').attr('class', d => {
            let classes = 'node';
            if (d.id === this.activeNode) classes += ' active';
            return classes;
        });
        
        // Simulation tick
        this.simulation.on('tick', () => {
            this.container.selectAll('.link')
                .attr('x1', d => d.source.x)
                .attr('y1', d => d.source.y)
                .attr('x2', d => d.target.x)
                .attr('y2', d => d.target.y);
            
            this.container.selectAll('.node-group')
                .attr('transform', d => `translate(${d.x},${d.y})`);
        });
    }
    
    createDrag() {
        return d3.drag()
            .on('start', (event, d) => {
                if (!event.active) this.simulation.alphaTarget(0.3).restart();
                d.fx = d.x;
                d.fy = d.y;
            })
            .on('drag', (event, d) => {
                d.fx = event.x;
                d.fy = event.y;
            })
            .on('end', (event, d) => {
                if (!event.active) this.simulation.alphaTarget(0);
                this.nodePositions.set(d.id, { x: d.fx, y: d.fy });
            });
    }
    
    handleNodeClick(nodeId) {
        if (this.currentMode === 'traversal') {
            this.setActiveNode(nodeId);
            this.updateVisualization();
        } else {
            // Search mode: expand neighbors
            this.visibleNodes.add(nodeId);
            this.expandParents();
            this.expandChildren();
        }
    }
}

// Initialize the explorer when the page loads
document.addEventListener('DOMContentLoaded', () => {
    new DependencyExplorer();
});