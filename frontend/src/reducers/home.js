import { HOME_PAGE_LOADED, HOME_PAGE_UNLOADED } from '../constants/actionTypes';

export default (state = {}, action) => {
  switch (action.type) {
    case HOME_PAGE_LOADED:
      if (action.error || !action.payload || !action.payload[0]) {
        return { ...state, tags: [] };
      }
      return {
        ...state,
        tags: action.payload[0].tags
      };
    case HOME_PAGE_UNLOADED:
      return {};
    default:
      return state;
  }
};
