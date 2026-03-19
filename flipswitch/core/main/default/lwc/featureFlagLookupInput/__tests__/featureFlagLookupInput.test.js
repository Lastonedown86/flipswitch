/* eslint-disable @lwc/lwc/prefer-custom-event */
import { createElement } from 'lwc';
import FeatureFlagLookupInput from 'c/featureFlagLookupInput';

describe('c-feature-flag-lookup-input', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.restoreAllMocks();
    });

    function createComponent(props = {}) {
        const element = createElement('c-feature-flag-lookup-input', {
            is: FeatureFlagLookupInput
        });
        Object.assign(element, props);
        document.body.appendChild(element);
        return element;
    }

    const MOCK_OPTIONS = [
        { label: 'System Administrator', value: '00e000000000001' },
        { label: 'Sales User', value: '00e000000000002' },
        { label: 'Support User', value: '00e000000000003' }
    ];

    it('renders label', async () => {
        const el = createComponent({ label: 'Profile', variant: 'static', options: MOCK_OPTIONS });
        await Promise.resolve();
        const label = el.shadowRoot.querySelector('label');
        expect(label.textContent).toContain('Profile');
    });

    it('shows dropdown on input focus (static mode)', async () => {
        const el = createComponent({ variant: 'static', options: MOCK_OPTIONS });
        await Promise.resolve();

        const input = el.shadowRoot.querySelector('input');
        input.dispatchEvent(new Event('focus'));
        await Promise.resolve();

        const dropdown = el.shadowRoot.querySelector('.lookup-dropdown');
        expect(dropdown).not.toBeNull();
        const options = el.shadowRoot.querySelectorAll('.lookup-option');
        expect(options.length).toBe(3);
    });

    it('filters options based on search text (static mode)', async () => {
        const el = createComponent({ variant: 'static', options: MOCK_OPTIONS });
        await Promise.resolve();

        const input = el.shadowRoot.querySelector('input');
        input.value = 'admin';
        input.dispatchEvent(new Event('input'));
        input.dispatchEvent(new Event('focus'));
        await Promise.resolve();

        const options = el.shadowRoot.querySelectorAll('.lookup-option');
        expect(options.length).toBe(1);
        expect(options[0].textContent).toContain('System Administrator');
    });

    it('selects option and shows pill', async () => {
        const changeSpy = jest.fn();
        const el = createComponent({ variant: 'static', options: MOCK_OPTIONS });
        el.addEventListener('change', changeSpy);
        await Promise.resolve();

        // Open dropdown
        const input = el.shadowRoot.querySelector('input');
        input.dispatchEvent(new Event('focus'));
        await Promise.resolve();

        // Click first option
        const option = el.shadowRoot.querySelector('.lookup-option');
        option.click();
        await Promise.resolve();

        // Verify pill appears
        const pills = el.shadowRoot.querySelectorAll('.pill');
        expect(pills.length).toBe(1);
        expect(pills[0].textContent).toContain('System Administrator');

        // Verify change event
        expect(changeSpy).toHaveBeenCalled();
        expect(changeSpy.mock.calls[0][0].detail.values).toEqual(['00e000000000001']);
    });

    it('removes pill on click', async () => {
        const changeSpy = jest.fn();
        const el = createComponent({
            variant: 'static',
            options: MOCK_OPTIONS,
            selectedValues: ['00e000000000001'],
            selectedPills: [{ label: 'System Administrator', value: '00e000000000001' }]
        });
        el.addEventListener('change', changeSpy);
        await Promise.resolve();

        // Verify pill exists
        let pills = el.shadowRoot.querySelectorAll('.pill');
        expect(pills.length).toBe(1);

        // Click remove
        const removeBtn = el.shadowRoot.querySelector('.pill__remove');
        removeBtn.click();
        await Promise.resolve();

        // Pill should be gone
        pills = el.shadowRoot.querySelectorAll('.pill');
        expect(pills.length).toBe(0);

        // Change event fired with empty array
        expect(changeSpy).toHaveBeenCalled();
        const lastCall = changeSpy.mock.calls[changeSpy.mock.calls.length - 1];
        expect(lastCall[0].detail.values).toEqual([]);
    });

    it('supports multi-select (multiple pills)', async () => {
        const changeSpy = jest.fn();
        const el = createComponent({ variant: 'static', options: MOCK_OPTIONS });
        el.addEventListener('change', changeSpy);
        await Promise.resolve();

        // Open dropdown and select first
        const input = el.shadowRoot.querySelector('input');
        input.dispatchEvent(new Event('focus'));
        await Promise.resolve();
        el.shadowRoot.querySelectorAll('.lookup-option')[0].click();
        await Promise.resolve();

        // Open again and select second
        input.dispatchEvent(new Event('focus'));
        await Promise.resolve();
        el.shadowRoot.querySelectorAll('.lookup-option')[1].click();
        await Promise.resolve();

        const pills = el.shadowRoot.querySelectorAll('.pill');
        expect(pills.length).toBe(2);

        const lastCall = changeSpy.mock.calls[changeSpy.mock.calls.length - 1];
        expect(lastCall[0].detail.values).toEqual(['00e000000000001', '00e000000000002']);
    });

    it('dispatches search event in search mode after debounce', async () => {
        jest.useFakeTimers();
        const searchSpy = jest.fn();
        const el = createComponent({ variant: 'search', placeholder: 'Search users…' });
        el.addEventListener('search', searchSpy);
        await Promise.resolve();

        const input = el.shadowRoot.querySelector('input');
        input.value = 'John';
        input.dispatchEvent(new Event('input'));
        await Promise.resolve();

        // Not yet — debounce hasn't fired
        expect(searchSpy).not.toHaveBeenCalled();

        // Advance debounce timer
        jest.advanceTimersByTime(350);
        await Promise.resolve();

        expect(searchSpy).toHaveBeenCalledTimes(1);
        expect(searchSpy.mock.calls[0][0].detail.searchTerm).toBe('John');

        jest.useRealTimers();
    });

    it('shows search results via setSearchResults API', async () => {
        const el = createComponent({ variant: 'search' });
        await Promise.resolve();

        el.setSearchResults([
            { label: 'John Doe', value: '005xx0001', sublabel: 'john@test.com' },
            { label: 'Jane Doe', value: '005xx0002', sublabel: 'jane@test.com' }
        ]);
        await Promise.resolve();

        const dropdown = el.shadowRoot.querySelector('.lookup-dropdown');
        expect(dropdown).not.toBeNull();
        const options = el.shadowRoot.querySelectorAll('.lookup-option');
        expect(options.length).toBe(2);
    });

    it('does not dispatch search for short terms', async () => {
        jest.useFakeTimers();
        const searchSpy = jest.fn();
        const el = createComponent({ variant: 'search' });
        el.addEventListener('search', searchSpy);
        await Promise.resolve();

        const input = el.shadowRoot.querySelector('input');
        input.value = 'J';
        input.dispatchEvent(new Event('input'));
        jest.advanceTimersByTime(350);
        await Promise.resolve();

        expect(searchSpy).not.toHaveBeenCalled();
        jest.useRealTimers();
    });

    it('closes dropdown on Escape key', async () => {
        const el = createComponent({ variant: 'static', options: MOCK_OPTIONS });
        await Promise.resolve();

        const input = el.shadowRoot.querySelector('input');
        input.dispatchEvent(new Event('focus'));
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.lookup-dropdown')).not.toBeNull();

        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.lookup-dropdown')).toBeNull();
    });
});
