export class ShowToastEvent extends CustomEvent {
    constructor(toast) {
        super('lightning__showtoast', {
            composed: true,
            cancelable: true,
            bubbles: true,
            detail: toast
        });
    }
}
