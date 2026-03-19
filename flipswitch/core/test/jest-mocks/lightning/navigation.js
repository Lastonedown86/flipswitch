export const CurrentPageReference = jest.fn();
export const NavigationMixin = (Base) => {
    return class extends Base {
        navigate = jest.fn();
        generateUrl = jest.fn();
    };
};
