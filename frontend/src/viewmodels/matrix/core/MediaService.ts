export interface IMediaService {
  pickMedia(): Promise<File | undefined>;
  pickFile(): Promise<File | undefined>;
}

export class BrowserMediaService implements IMediaService {
  private pick(accept: string | undefined): Promise<File | undefined> {
    if (typeof window === 'undefined') {
      return Promise.resolve(undefined);
    }
    return new Promise<File | undefined>((resolve) => {
      const input = document.createElement('input');
      input.type = 'file';
      if (accept) input.accept = accept;
      input.style.display = 'none';
      input.onchange = () => {
        const file = input.files?.[0];
        resolve(file ?? undefined);
        if (input.parentNode) {
          input.parentNode.removeChild(input);
        }
      };
      input.onclick = (e) => {
        e.stopPropagation();
      };
      document.body.appendChild(input);
      input.click();
    });
  }

  async pickMedia(): Promise<File | undefined> {
    return this.pick('image/*,video/*');
  }

  async pickFile(): Promise<File | undefined> {
    return this.pick(undefined);
  }
}
