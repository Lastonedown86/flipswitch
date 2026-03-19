import { LightningElement, api, track } from 'lwc';

const DEBOUNCE_MS = 300;

/**
 * @description Reusable multi-select lookup/combobox input with pill chips.
 *              Supports two modes:
 *              - "static"  — options provided up-front, filtered client-side
 *              - "search"  — options fetched via a callback on keystroke (typeahead)
 *
 *              Fires `change` event with detail { values: [...selectedValues] }
 *              whenever the selection changes.
 */
export default class FeatureFlagLookupInput extends LightningElement {
    /** @api Display label above the input */
    @api label = '';

    /** @api Help text shown via lightning-helptext */
    @api fieldLevelHelp = '';

    /** @api Placeholder text for the search input */
    @api placeholder = 'Search…';

    /** @api "static" or "search" */
    @api variant = 'static';

    /**
     * @api For static mode: array of { label, value, sublabel? }
     *      Set by parent — when options change, dropdown updates.
     */
    @api
    get options() {
        return this._options;
    }
    set options(val) {
        this._options = val ?? [];
    }

    /**
     * @api Currently selected values (array of value strings).
     *      Parent sets this to pre-populate pills (e.g. when editing an existing rule).
     */
    @api
    get selectedValues() {
        return this._selectedValues;
    }
    set selectedValues(val) {
        this._selectedValues = val ?? [];
    }

    /**
     * @api Pre-resolved pills for display. Array of { label, value, sublabel? }
     *      Used when editing existing rules to show readable names for IDs.
     */
    @api
    get selectedPills() {
        return this._selectedPills;
    }
    set selectedPills(val) {
        this._selectedPills = val ?? [];
    }

    // ─── Internal state ──────────────────────────────────────────────────────

    _options = [];
    _selectedValues = [];
    _selectedPills = [];

    @track searchTerm = '';
    @track searchResults = [];
    @track dropdownOpen = false;
    @track isSearching = false;
    @track focusedIndex = -1;

    _debounceTimer;

    // ─── Getters ─────────────────────────────────────────────────────────────

    get isSearchType() {
        return this.variant === 'search';
    }

    get computedPlaceholder() {
        if (this.hasPills) {
            return 'Add more…';
        }
        return this.placeholder;
    }

    get noResultsMessage() {
        if (!this.searchTerm || this.searchTerm.length < 2) {
            return 'Type at least 2 characters to search';
        }
        return 'No results found';
    }

    get filteredOptions() {
        const selectedSet = new Set(this._selectedValues);
        let source;
        if (this.isSearchType) {
            source = this.searchResults;
        } else {
            const term = (this.searchTerm || '').toLowerCase();
            source = this._options.filter(
                (opt) =>
                    opt.label.toLowerCase().includes(term) ||
                    (opt.sublabel && opt.sublabel.toLowerCase().includes(term))
            );
        }
        return source.map((opt, idx) => ({
            ...opt,
            selected: selectedSet.has(opt.value),
            itemClass: `lookup-option${idx === this.focusedIndex ? ' lookup-option--focused' : ''}${selectedSet.has(opt.value) ? ' lookup-option--selected' : ''}`
        }));
    }

    get hasFilteredOptions() {
        return this.filteredOptions.length > 0;
    }

    get pills() {
        // Merge resolved pills with selected values
        const pillMap = new Map();
        for (const p of this._selectedPills) {
            pillMap.set(p.value, p);
        }
        // For static mode, we can resolve from options
        if (!this.isSearchType) {
            for (const opt of this._options) {
                if (!pillMap.has(opt.value)) {
                    pillMap.set(opt.value, opt);
                }
            }
        }
        return this._selectedValues.map((val) => pillMap.get(val) || { label: val, value: val }).filter(Boolean);
    }

    get hasPills() {
        return this._selectedValues.length > 0;
    }

    // ─── Event handlers ──────────────────────────────────────────────────────

    handleInputFocus() {
        if (!this.isSearchType) {
            this.dropdownOpen = true;
        }
        // For search type, only open when there are results
        if (this.isSearchType && this.searchResults.length > 0) {
            this.dropdownOpen = true;
        }
    }

    handleSearchInput(event) {
        this.searchTerm = event.target.value;
        this.focusedIndex = -1;

        if (this.isSearchType) {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            clearTimeout(this._debounceTimer);
            if (this.searchTerm.length < 2) {
                this.searchResults = [];
                this.dropdownOpen = false;
                return;
            }
            this.isSearching = true;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this._debounceTimer = setTimeout(() => {
                this.dispatchEvent(
                    new CustomEvent('search', {
                        detail: { searchTerm: this.searchTerm }
                    })
                );
            }, DEBOUNCE_MS);
        } else {
            // Static filter — just open dropdown
            this.dropdownOpen = true;
        }
    }

    /**
     * @api Called by parent after resolving search results from Apex.
     *      Sets the dropdown options for search mode.
     */
    @api
    setSearchResults(results) {
        this.searchResults = results ?? [];
        this.isSearching = false;
        this.dropdownOpen = this.searchResults.length > 0;
    }

    handleKeyDown(event) {
        if (!this.dropdownOpen) return;
        const opts = this.filteredOptions;
        switch (event.key) {
            case 'ArrowDown':
                event.preventDefault();
                this.focusedIndex = Math.min(this.focusedIndex + 1, opts.length - 1);
                break;
            case 'ArrowUp':
                event.preventDefault();
                this.focusedIndex = Math.max(this.focusedIndex - 1, 0);
                break;
            case 'Enter':
                event.preventDefault();
                if (this.focusedIndex >= 0 && this.focusedIndex < opts.length) {
                    this._toggleSelection(opts[this.focusedIndex]);
                }
                break;
            case 'Escape':
                this.dropdownOpen = false;
                this.focusedIndex = -1;
                break;
            default:
                break;
        }
    }

    handleOptionHover(event) {
        const val = event.currentTarget.dataset.value;
        const idx = this.filteredOptions.findIndex((o) => o.value === val);
        if (idx >= 0) {
            this.focusedIndex = idx;
        }
    }

    handleSelectOption(event) {
        const val = event.currentTarget.dataset.value;
        const opt = this.filteredOptions.find((o) => o.value === val);
        if (opt) {
            this._toggleSelection(opt);
        }
    }

    handleRemovePill(event) {
        const val = event.currentTarget.dataset.value;
        this._selectedValues = this._selectedValues.filter((v) => v !== val);
        this._selectedPills = this._selectedPills.filter((p) => p.value !== val);
        this._fireChange();
    }

    // Close dropdown when clicking outside
    connectedCallback() {
        this._outsideClickHandler = (event) => {
            if (!this.template.querySelector('.lookup-container')?.contains(event.target)) {
                this.dropdownOpen = false;
                this.focusedIndex = -1;
            }
        };
        // eslint-disable-next-line @lwc/lwc/no-document-query
        document.addEventListener('click', this._outsideClickHandler, true);
    }

    disconnectedCallback() {
        // eslint-disable-next-line @lwc/lwc/no-document-query
        document.removeEventListener('click', this._outsideClickHandler, true);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        clearTimeout(this._debounceTimer);
    }

    // ─── Private helpers ─────────────────────────────────────────────────────

    _toggleSelection(opt) {
        const isSelected = this._selectedValues.includes(opt.value);
        if (isSelected) {
            this._selectedValues = this._selectedValues.filter((v) => v !== opt.value);
            this._selectedPills = this._selectedPills.filter((p) => p.value !== opt.value);
        } else {
            this._selectedValues = [...this._selectedValues, opt.value];
            // Store the full option as a pill so we can display its label
            if (!this._selectedPills.find((p) => p.value === opt.value)) {
                this._selectedPills = [
                    ...this._selectedPills,
                    {
                        label: opt.label,
                        value: opt.value,
                        sublabel: opt.sublabel
                    }
                ];
            }
        }
        this.searchTerm = '';
        this._fireChange();

        // For search mode, close dropdown after selection
        if (this.isSearchType) {
            this.dropdownOpen = false;
            this.searchResults = [];
        }
    }

    _fireChange() {
        this.dispatchEvent(
            new CustomEvent('change', {
                detail: { values: [...this._selectedValues] }
            })
        );
    }
}
