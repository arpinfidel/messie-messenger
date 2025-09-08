export interface IMediaService {
  pickImage(): Promise<File | undefined>;
}

export class BrowserMediaService implements IMediaService {
  async pickImage(): Promise<File | undefined> {
    if (typeof window === 'undefined') {
      return undefined;
    }
    return new Promise<File | undefined>((resolve) => {
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = 'image/*';
      input.style.display = 'none';
      input.onchange = () => {
        const file = input.files?.[0];
        resolve(file ?? undefined);
        if (input.parentNode) {
          input.parentNode.removeChild(input);
        }
      };
      input.onclick = (e) => {
        // Prevent the event from bubbling further if inserted into DOM
        e.stopPropagation();
      };
      document.body.appendChild(input);
      input.click();
    });
  }
}
